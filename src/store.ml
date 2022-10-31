open Lwt.Syntax

let ( // ) = Filename.concat

module Store = Irmin_fs_unix.Make (Schema)
module Info = Irmin_unix.Info (Store.Info)
module Hash = Store.Hash

type t = { mutable db : Store.t; mutable branch : string; author : string }
type hash = Store.Hash.t

let store { db; _ } = db
let branch { branch; _ } = branch
let repo { db; _ } = Store.repo db

exception Validation_error of string

let info t = Info.v ~author:t.author

let hash_or_path ~hash ~path = function
  | [ hash_or_path ] -> (
      match Irmin.Type.of_string Store.Hash.t hash_or_path with
      | Ok x -> Error.mk @@ fun () -> hash x
      | Error _ -> Error.mk @@ fun () -> path [ hash_or_path ])
  | x -> Error.mk @@ fun () -> path x

let root t =
  let conf = Store.Repo.config (repo t) in
  Irmin.Backend.Conf.get conf Irmin_fs.Conf.Key.root

let try_mkdir ?(mode = 0o755) path =
  Lwt.catch (fun () -> Lwt_unix.mkdir path mode) (fun _ -> Lwt.return_unit)

let v ?(author = "wasmstore") ?(branch = Store.Branch.main) root =
  let config = Irmin_fs.config root in
  let* repo = Store.Repo.v config in
  let* db = Store.of_branch repo branch in
  let* () = try_mkdir (root // "tmp") in
  let* () = try_mkdir (root // "objects") in
  Lwt.return { db; branch; author }

let verify_string wasm =
  match Rust.wasm_verify_string wasm with
  | Ok () -> ()
  | Error e -> raise (Validation_error e)

let verify_file filename =
  match Rust.wasm_verify_file filename with
  | Ok () -> ()
  | Error e -> raise (Validation_error e)

let snapshot { db; _ } = Store.Head.get db

let restore t ?path commit =
  match path with
  | None | Some [] -> Error.mk @@ fun () -> Store.Head.set t.db commit
  | Some path ->
      let info = info t "Restore %a" (Irmin.Type.pp Store.Path.t) path in
      let tree = Store.Commit.tree commit in
      Error.mk @@ fun () ->
      Store.with_tree_exn ~info t.db path (fun _ ->
          Store.Tree.find_tree tree path)

let tree_opt_equal = Irmin.Type.(unstage (equal (option Store.Tree.t)))

let rollback t ?(path = []) () : unit Lwt.t =
  let* lm = Store.last_modified ~n:2 t.db path in
  match lm with
  | [ _; commit ] -> restore t ~path commit
  | _ ->
      let info = info t "Rollback %a" Irmin.Type.(pp Store.Path.t) path in
      Error.mk @@ fun () ->
      Store.with_tree_exn ~info t.db path (fun _ ->
          Lwt.return_some @@ Store.Tree.empty ())

let path_of_hash hash =
  let hash' = Irmin.Type.to_string Store.Hash.t hash in
  let a = String.sub hash' 0 2 in
  let b = String.sub hash' 2 (String.length hash' - 2) in
  "objects" // a // b

let get_hash_and_filename t path =
  let* hash = hash_or_path ~hash:Lwt.return_some ~path:(Store.hash t.db) path in
  match hash with
  | None -> Lwt.return_none
  | Some hash ->
      let path = path_of_hash hash in
      Lwt.return_some (hash, path)

let set_path t path hash =
  let* tree = Store.Tree.of_hash (repo t) (`Contents (hash, ())) in
  match tree with
  | None -> failwith "hash mismatch"
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
      let* () = try_mkdir (Filename.dirname dest) in
      Lwt_unix.rename tmp dest
    else Lwt.return_unit
  in
  let* () = set_path t path hash in
  Lwt.return hash

let add t path wasm =
  let () = verify_string wasm in
  let info = info t "Add %a" (Irmin.Type.pp Store.Path.t) path in
  let f hash =
    Error.mk @@ fun () ->
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
        | _ -> Error.mk @@ fun () -> Store.set_exn t.db path wasm ~info)
      path
  in
  Store.Contents.hash wasm

let find_hash { db; _ } hash = Store.Contents.of_hash (Store.repo db) hash
let find t path = hash_or_path ~hash:(find_hash t) ~path:(Store.find t.db) path

let hash t path =
  hash_or_path ~hash:(fun x -> Lwt.return_some x) ~path:(Store.hash t.db) path

let hash_eq = Irmin.Type.(unstage (equal Store.Hash.t))

let remove t path =
  let info = info t "Remove %a" (Irmin.Type.pp Store.Path.t) path in
  let hash h =
    (* Search through the current tree for any contents that match [h] *)
    let rec aux tree path =
      match Store.Tree.destruct tree with
      | `Contents (c, _) ->
          let hash = Store.Tree.Contents.hash c in
          if hash_eq hash h then Store.Tree.remove tree path
          else Lwt.return tree
      | `Node _ ->
          let* items = Store.Tree.list tree [] in
          Lwt_list.fold_left_s
            (fun tree -> function p, _ -> aux tree (Store.Path.rcons path p))
            tree items
    in
    let* tree = Store.tree t.db in
    let* tree = aux tree [] in
    Error.mk @@ fun () ->
    Store.test_and_set_tree_exn t.db path ~test:(Some tree) ~set:(Some tree)
      ~info
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

let contains_hash t hash =
  let+ res =
    get_hash_and_filename t [ Irmin.Type.to_string Store.Hash.t hash ]
  in
  Option.is_some res

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
