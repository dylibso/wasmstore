open Lwt.Syntax
open Store

let delete { db; _ } branch = Store.Branch.remove (Store.repo db) branch

let create t branch =
  let* exists = Store.Branch.mem (Store.repo t.db) branch in
  if exists then Lwt.return_error (`Msg "Branch already exists")
  else
    let info = Info.v "Create branch %s" branch in
    let* db = Store.of_branch (Store.repo t.db) branch in
    let* _ = Store.merge_with_branch db ~info t.branch in
    Lwt.return_ok { db; branch }

let switch t branch =
  let* exists = Store.Branch.mem (Store.repo t.db) branch in
  let* () =
    if not exists then
      let* _ = create t branch in
      Lwt.return_unit
    else Lwt.return_unit
  in
  let+ db = Store.of_branch (Store.repo t.db) branch in
  t.branch <- branch;
  t.db <- db

let list t = Store.Branch.list (Store.repo t.db)
