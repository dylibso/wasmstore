open Lwt.Syntax

let ( // ) = Filename.concat

module Schema = struct
  include Irmin.Schema.KV (Irmin.Contents.String)
  module Hash = Irmin.Hash.SHA256
  module Key = Irmin.Key.Of_hash (Hash)
  module Node = Irmin.Node.Generic_key.Make (Hash) (Path) (Metadata)
  module Commit = Irmin.Commit.Generic_key.Make (Hash)
end

module Store = Irmin_fs_unix.Make (Schema)
module Info = Irmin_unix.Info (Store.Info)

type t = { mutable db : Store.t; mutable branch : string }
type hash = Store.Hash.t

let store { db; _ } = db
let branch { branch; _ } = branch
let repo { db; _ } = Store.repo db

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
  let+ db = Store.of_branch repo branch in
  { db; branch }

let verify wasm =
  let m = Wasm.Decode.decode "wasm" wasm in
  Wasm.Valid.check_module m

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

let add { db; _ } path wasm =
  let () = verify wasm in
  let info = Info.v "Add %a" (Irmin.Type.pp Store.Path.t) path in
  let f hash =
    Store.set_exn db [ Irmin.Type.to_string Store.Hash.t hash ] wasm ~info
  in
  let+ () =
    hash_or_path ~hash:f
      ~path:(fun path ->
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

let remove { db; _ } path =
  let info = Info.v "Remove %a" (Irmin.Type.pp Store.Path.t) path in
  let hash h =
    let rec aux tree path =
      match Store.Tree.destruct tree with
      | `Contents (c, _) ->
          let hash = Store.Tree.Contents.hash c in
          if hash = h then Store.Tree.remove tree path else Lwt.return tree
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
