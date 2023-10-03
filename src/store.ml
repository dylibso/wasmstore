open Lwt.Syntax

let ( // ) = Filename.concat

module Store = Irmin_fs_unix.Make (Schema)
module Info = Irmin_unix.Info (Store.Info)
module Hash = Store.Hash

type t = {
  mutable db : Store.t;
  env : Eio_unix.Stdenv.base;
  mutable branch : string;
  author : string;
}

type hash = Store.Hash.t

let store { db; _ } = db
let branch { branch; _ } = branch
let repo { db; _ } = Store.repo db

exception Validation_error of string

let info t = Info.v ~author:t.author

let hash_or_path ~hash ~path = function
  | [ hash_or_path ] -> (
      match Irmin.Type.of_string Store.Hash.t hash_or_path with
      | Ok x -> Error.mk_lwt @@ fun () -> hash x
      | Error _ -> Error.mk_lwt @@ fun () -> path [ hash_or_path ])
  | x -> Error.mk_lwt @@ fun () -> path x

let root t =
  let conf = Store.Repo.config (repo t) in
  Irmin.Backend.Conf.get conf Irmin_fs.Conf.Key.root

let try_mkdir ?(mode = 0o755) ~env path =
  let open Eio.Path in
  try Eio.Path.mkdir ~perm:mode (Eio.Stdenv.fs env / path) with _ -> ()

let v ?(author = "wasmstore") ?(branch = Store.Branch.main) root ~env =
  let () = try_mkdir root ~env in
  let config = Irmin_fs.config root in
  let repo = Lwt_eio.run_lwt @@ fun () -> Store.Repo.v config in
  let db = Lwt_eio.run_lwt @@ fun () -> Store.of_branch repo branch in
  let () = try_mkdir ~env (root // "tmp") in
  let () = try_mkdir ~env (root // "objects") in
  { db; branch; author; env }

let verify_string wasm =
  match Rust.verify_string wasm with
  | Ok () -> ()
  | Error (`Msg e) -> raise (Validation_error e)

let verify_file filename =
  match Rust.verify_file filename with
  | Ok () -> ()
  | Error (`Msg e) -> raise (Validation_error e)

let snapshot { db; _ } = Lwt_eio.run_lwt @@ fun () -> Store.Head.get db

let restore t ?path commit =
  match path with
  | None | Some [] ->
      Error.mk @@ fun () ->
      Lwt_eio.run_lwt @@ fun () -> Store.Head.set t.db commit
  | Some path ->
      Lwt_eio.run_lwt @@ fun () ->
      let info = info t "Restore %a" (Irmin.Type.pp Store.Path.t) path in
      let parents = Store.Commit.parents commit in
      let* parents =
        Lwt_list.filter_map_s (Store.Commit.of_key (Store.repo t.db)) parents
      in
      let tree = Store.Commit.tree commit in
      Error.mk_lwt @@ fun () ->
      Store.with_tree_exn ~parents ~info t.db path (fun _ ->
          Store.Tree.find_tree tree path)

let tree_opt_equal = Irmin.Type.(unstage (equal (option Store.Tree.t)))

let rollback t ?(path = []) n : unit =
  let lm =
    Lwt_eio.run_lwt @@ fun () -> Store.last_modified ~n:(n + 1) t.db path
  in
  match List.rev lm with
  | commit :: _ :: _ -> restore t ~path commit
  | [ _ ] | [] ->
      Lwt_eio.run_lwt @@ fun () ->
      let info = info t "Rollback %a" Irmin.Type.(pp Store.Path.t) path in
      Error.mk_lwt @@ fun () ->
      Store.with_tree_exn ~info t.db path (fun _ -> Lwt.return_none)

let path_of_hash hash =
  let hash' = Irmin.Type.to_string Store.Hash.t hash in
  let a = String.sub hash' 0 2 in
  let b = String.sub hash' 2 (String.length hash' - 2) in
  "objects" // a // b

let hash_eq = Irmin.Type.(unstage (equal Store.Hash.t))

let contains_hash t hash =
  let rec aux tree =
    match Store.Tree.destruct tree with
    | `Contents (c, _) ->
        let hash' = Store.Tree.Contents.hash c in
        Lwt.return @@ hash_eq hash hash'
    | `Node _ ->
        let* items = Store.Tree.list tree [] in
        Lwt_list.exists_p (fun (_, tree') -> aux tree') items
  in
  let* tree = Store.tree t.db in
  aux tree

let get_hash_and_filename t path =
  let* hash = hash_or_path ~hash:Lwt.return_some ~path:(Store.hash t.db) path in
  match hash with
  | None -> Lwt.return_none
  | Some hash ->
      let+ exists = contains_hash t hash in
      if exists then
        let path = path_of_hash hash in
        Some (hash, path)
      else None

let set_path t path hash =
  let* tree = Store.Tree.of_hash (repo t) (`Contents (hash, ())) in
  match tree with
  | None -> Error.throw (`Msg "hash mismatch")
  | Some tree ->
      let info = info t "Import %a" (Irmin.Type.pp Store.Path.t) path in
      Store.set_tree_exn t.db path tree ~info

let import t path stream =
  let hash = ref (Digestif.SHA256.init ()) in
  let tmp =
    Filename.temp_file ~temp_dir:(root t // "tmp") "wasmstore" "import"
  in
  let* () =
    Lwt_io.with_file
      ~flags:Unix.[ O_CREAT; O_WRONLY ]
      ~mode:Output tmp
      (fun oc ->
        Lwt_stream.iter_s
          (fun s ->
            hash := Digestif.SHA256.feed_string !hash s;
            Lwt_io.write oc s)
          stream)
  in
  let hash = Digestif.SHA256.get !hash in
  let hash =
    Irmin.Hash.SHA256.unsafe_of_raw_string (Digestif.SHA256.to_raw_string hash)
  in
  let dest = root t // path_of_hash hash in
  let* exists = Lwt_unix.file_exists dest in
  let* () =
    if not exists then
      let () =
        try verify_file tmp
        with e ->
          Unix.unlink tmp;
          raise e
      in
      let () = try_mkdir ~env:t.env (Filename.dirname dest) in
      Lwt_unix.rename tmp dest
    else Lwt.return_unit
  in
  let* () = set_path t path hash in
  Lwt.return hash

let add t path wasm =
  let () = verify_string wasm in
  let info = info t "Add %a" (Irmin.Type.pp Store.Path.t) path in
  let f hash =
    Error.mk_lwt @@ fun () ->
    Store.set_exn t.db [ Irmin.Type.to_string Store.Hash.t hash ] wasm ~info
  in
  let+ () =
    hash_or_path ~hash:f
      ~path:(fun path ->
        (* If the path is empty then just add the contents to the store without
           associating it with a path *)
        match path with
        | [] ->
            Store.Backend.Repo.batch (repo t) (fun contents _ _ ->
                let+ _ = Store.save_contents contents wasm in
                ())
        | _ -> Error.mk_lwt @@ fun () -> Store.set_exn t.db path wasm ~info)
      path
  in
  Store.Contents.hash wasm

let set t path hash =
  let* tree = Store.Tree.of_hash (repo t) (`Contents (hash, ())) in
  let f path =
    match tree with
    | None -> Error.throw (`Msg "hash mismatch")
    | Some tree ->
        let info =
          info t "Set %a %a"
            (Irmin.Type.pp Store.Path.t)
            path
            (Irmin.Type.pp Store.Hash.t)
            hash
        in
        Store.set_tree_exn t.db path tree ~info
  in
  hash_or_path
    ~hash:(fun _ ->
      Error.throw (`Msg "A hash path should not be used with `set` command"))
    ~path:f path

let find_hash t hash =
  let* contains = contains_hash t hash in
  if contains then Store.Contents.of_hash (Store.repo t.db) hash
  else Lwt.return_none

let find t path = hash_or_path ~hash:(find_hash t) ~path:(Store.find t.db) path

let hash t path =
  hash_or_path ~hash:(fun x -> Lwt.return_some x) ~path:(Store.hash t.db) path

let remove t path =
  let info = info t "Remove %a" (Irmin.Type.pp Store.Path.t) path in
  let hash h =
    (* Search through the current tree for any contents that match [h] *)
    let rec aux tree =
      match Store.Tree.destruct tree with
      | `Contents (c, _) ->
          let hash = Store.Tree.Contents.hash c in
          if hash_eq hash h then Store.Tree.remove tree [] else Lwt.return tree
      | `Node _ ->
          let* items = Store.Tree.list tree [] in
          Lwt_list.fold_left_s
            (fun tree -> function
              | p, tree' ->
                  let* x = aux tree' in
                  Store.Tree.add_tree tree [ p ] x)
            tree items
    in
    let* tree = Store.tree t.db in
    let is_empty = Store.Tree.is_empty tree in
    let* tree' = aux tree in
    Error.mk_lwt @@ fun () ->
    Store.test_and_set_tree_exn t.db []
      ~test:(if is_empty then None else Some tree)
      ~set:(Some tree') ~info
  in
  hash_or_path ~path:(Store.remove_exn t.db ~info) ~hash path

let list { db; _ } path =
  let rec aux path =
    let* items = Store.list db path in
    let+ items =
      Lwt_list.map_s
        (fun (k, v) ->
          let full = Store.Path.rcons path k in
          let* kind = Store.Tree.kind v [] in
          match kind with
          | None -> Lwt.return []
          | Some `Contents -> Lwt.return [ (full, Store.Tree.hash v) ]
          | Some `Node -> aux full)
        items
    in
    List.flatten items
  in
  aux path

let contains t path =
  hash_or_path
    ~hash:(fun h -> contains_hash t h)
    ~path:(fun path -> Store.mem t.db path)
    path

let merge t branch =
  let info = info t "Merge %s" branch in
  Store.merge_with_branch t.db ~info branch

let with_branch t branch = { t with branch }
let with_author t author = { t with author }

module Hash_set = Set.Make (struct
  type t = Hash.t

  let compare = Irmin.Type.(unstage @@ compare Hash.t)
end)

let versions t path =
  let* lm = Store.last_modified t.db ~n:max_int path in
  let hashes = ref Hash_set.empty in
  Lwt_list.filter_map_s
    (fun commit ->
      let* store = Store.of_commit commit in
      let* hash = Store.hash store path in
      match hash with
      | None -> Lwt.return_none
      | Some h ->
          if Hash_set.mem h !hashes then Lwt.return_none
          else
            let () = hashes := Hash_set.add h !hashes in
            Lwt.return_some (h, `Commit (Store.Commit.hash commit)))
    lm

let version t path index =
  let+ versions = versions t path in
  List.nth_opt versions index

module Commit_info = struct
  type t = {
    hash : Hash.t;
    parents : Hash.t list;
    author : string;
    date : int64;
    message : string;
  }
  [@@deriving irmin]
end

let commit_info t hash =
  let* commit =
    Lwt.catch
      (fun () -> Store.Commit.of_hash (repo t) hash)
      (function Assert_failure _ -> Lwt.return_none | exn -> raise exn)
  in
  match commit with
  | Some commit ->
      let parents = Store.Commit.parents commit in
      let info = Store.Commit.info commit in
      Lwt.return_some
        Commit_info.
          {
            hash;
            parents;
            author = Store.Info.author info;
            date = Store.Info.date info;
            message = Store.Info.message info;
          }
  | None -> Lwt.return_none
