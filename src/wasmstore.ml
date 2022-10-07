open Lwt.Syntax
module Store = Irmin_git_unix.FS.KV (Irmin.Contents.String)
module Info = Irmin_unix.Info (Store.Info)

type t = { db : Store.t }
type hash = Store.Hash.t

let v ~root =
  let config = Irmin_git.config root in
  let* repo = Store.Repo.v config in
  let+ db = Store.main repo in
  { db }

let verify wasm =
  let script = Wasm.Parse.string_to_module wasm in
  match script.Wasm.Source.it with
  | Textual t -> Wasm.Valid.check_module t
  | _ -> assert false

let add { db } path wasm =
  let () = verify wasm in
  let info = Info.v "Add %a" (Irmin.Type.pp Store.Path.t) path in
  let+ () = Store.set_exn db path wasm ~info in
  Store.Contents.hash wasm

let find_hash { db } hash = Store.Contents.of_hash (Store.repo db) hash
let find { db } path = Store.find db path

let remove { db } path =
  let info = Info.v "Added %a" (Irmin.Type.pp Store.Path.t) path in
  Store.remove_exn db path ~info

let list { db } path =
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
