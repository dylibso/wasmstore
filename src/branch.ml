open Store

let delete { db; _ } branch =
  Lwt_eio.run_lwt @@ fun () -> Store.Branch.remove (Store.repo db) branch

let create t branch =
  let exists =
    Lwt_eio.run_lwt @@ fun () -> Store.Branch.mem (Store.repo t.db) branch
  in
  if exists then Error (`Msg "Branch already exists")
  else
    let info = Info.v "Create branch %s" branch in
    let db =
      Lwt_eio.run_lwt @@ fun () -> Store.of_branch (Store.repo t.db) branch
    in
    let _ =
      Lwt_eio.run_lwt @@ fun () -> Store.merge_with_branch db ~info t.branch
    in
    Ok { t with db; branch }

let switch t branch =
  let exists =
    Lwt_eio.run_lwt @@ fun () -> Store.Branch.mem (Store.repo t.db) branch
  in
  let () =
    if not exists then
      let _ = create t branch in
      ()
    else ()
  in
  let db =
    Lwt_eio.run_lwt @@ fun () -> Store.of_branch (Store.repo t.db) branch
  in
  t.branch <- branch;
  t.db <- db

let list t = Lwt_eio.run_lwt @@ fun () -> Store.Branch.list (Store.repo t.db)
