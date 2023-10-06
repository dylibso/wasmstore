open Lwt.Syntax
open Store

let delete { db; _ } branch =
  Lwt_eio.run_lwt @@ fun () -> Store.Branch.remove (Store.repo db) branch

let create t branch =
  Lwt_eio.run_lwt @@ fun () ->
  let* exists = Store.Branch.mem (Store.repo t.db) branch in
  if exists then Lwt.return_error (`Msg "Branch already exists")
  else
    let info = Info.v "Create branch %s" branch in
    let* db = Store.of_branch (Store.repo t.db) branch in
    let* _ = Store.merge_with_branch db ~info t.branch in
    Lwt.return_ok { t with db; branch }

let switch t branch =
  let exists =
    Lwt_eio.run_lwt @@ fun () -> Store.Branch.mem (Store.repo t.db) branch
  in
  let () =
    if not exists then
      let _ = create t branch in
      ()
  in
  let db =
    Lwt_eio.run_lwt @@ fun () -> Store.of_branch (Store.repo t.db) branch
  in
  t.branch <- branch;
  t.db <- db

let list t = Lwt_eio.run_lwt @@ fun () -> Store.Branch.list (Store.repo t.db)
