open Lwt.Syntax

let ( // ) = Filename.concat

module Store = Irmin_fs_unix.Make (Schema)
module Info = Irmin_unix.Info (Store.Info)
module Hash = Store.Hash

type t = { mutable db : Store.t; mutable branch : string }
type hash = Store.Hash.t

let store { db; _ } = db
let branch { branch; _ } = branch
let repo { db; _ } = Store.repo db

exception Validation_error of string

let hash_or_path ~hash ~path = function
  | [ hash_or_path ] -> (
      match Irmin.Type.of_string Store.Hash.t hash_or_path with
      | Ok x -> hash x
      | Error _ -> path [ hash_or_path ])
  | x -> path x

let root t =
  let conf = Store.Repo.config (repo t) in
  Irmin.Backend.Conf.get conf Irmin_fs.Conf.Key.root

let v ?(branch = Store.Branch.main) root =
  let config = Irmin_fs.config root in
  let* repo = Store.Repo.v config in
  let* db = Store.of_branch repo branch in
  let* () =
    Lwt.catch
      (fun () -> Lwt_unix.mkdir (root // "tmp") 0o755)
      (fun _ -> Lwt.return_unit)
  in
  let* () =
    Lwt.catch
      (fun () -> Lwt_unix.mkdir (root // "objects") 0o755)
      (fun _ -> Lwt.return_unit)
  in
  Lwt.return { db; branch }

let verify_string wasm =
  match Rust.wasm_verify_string wasm with
  | Ok () -> ()
  | Error e -> raise (Validation_error e)

let verify_file filename =
  match Rust.wasm_verify_file filename with
  | Ok () -> ()
  | Error e -> raise (Validation_error e)

let snapshot { db; _ } = Store.Head.get db
let restore { db; _ } commit = Store.Head.set db commit

let get_hash_and_filename t path =
  let* hash = hash_or_path ~hash:Lwt.return_some ~path:(Store.hash t.db) path in
  match hash with
  | None -> Lwt.return_none
  | Some hash ->
      let hash' = Irmin.Type.to_string Store.Hash.t hash in
      let a = String.sub hash' 0 2 in
      let b = String.sub hash' 2 (String.length hash' - 2) in
      Lwt.return_some (hash, "objects" // a // b)

let set_path t path hash =
  let* tree = Store.Tree.of_hash (repo t) (`Contents (hash, ())) in
  match tree with
  | None -> failwith "hash mismatch"
  | Some tree ->
      let info = Info.v "Import %a" (Irmin.Type.pp Store.Path.t) path in
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
  let hash' =
    Irmin.Hash.SHA256.unsafe_of_raw_string (Digestif.SHA256.to_raw_string hash)
  in
  let hash = Digestif.SHA256.to_hex hash in
  let a = String.sub hash 0 2 in
  let b = String.sub hash 2 (String.length hash - 2) in
  let dest = root t // "objects" // a // b in
  let* exists = Lwt_unix.file_exists dest in
  let* () =
    if not exists then
      let () =
        try verify_file tmp
        with e ->
          Unix.unlink tmp;
          raise e
      in
      let* () =
        Lwt.catch
          (fun () -> Lwt_unix.mkdir (Filename.dirname dest) 0o755)
          (fun _ -> Lwt.return_unit)
      in
      Lwt_unix.rename tmp dest
    else Lwt.return_unit
  in
  let* () = set_path t path hash' in
  Lwt.return hash'

let add { db; _ } path wasm =
  let () = verify_string wasm in
  let info = Info.v "Add %a" (Irmin.Type.pp Store.Path.t) path in
  let f hash =
    Store.set_exn db [ Irmin.Type.to_string Store.Hash.t hash ] wasm ~info
  in
  let+ () =
    hash_or_path ~hash:f
      ~path:(fun path ->
        (* If the path is empty then just add the contents to the store without
           associating it with a path *)
        if path = [] then
          Store.Backend.Repo.batch (Store.repo db) (fun contents _ _ ->
              let+ _ = Store.save_contents contents wasm in
              ())
        else Store.set_exn db path wasm ~info)
      path
  in
  Store.Contents.hash wasm

let find_hash { db; _ } hash = Store.Contents.of_hash (Store.repo db) hash
let find t path = hash_or_path ~hash:(find_hash t) ~path:(Store.find t.db) path

let hash t path =
  hash_or_path ~hash:(fun x -> Lwt.return_some x) ~path:(Store.hash t.db) path

let hash_eq = Irmin.Type.(unstage (equal Store.Hash.t))

let remove { db; _ } path =
  let info = Info.v "Remove %a" (Irmin.Type.pp Store.Path.t) path in
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
    let* tree = Store.tree db in
    let* tree = aux tree [] in
    Store.test_and_set_tree_exn db path ~test:(Some tree) ~set:(Some tree) ~info
  in
  hash_or_path ~path:(Store.remove_exn db ~info) ~hash path

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

let merge { db; _ } branch =
  let info = Info.v "Merge %s" branch in
  Store.merge_with_branch db ~info branch

let with_branch t branch =
  let root = root t in
  v ~branch root
