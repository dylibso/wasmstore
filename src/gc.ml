open Lwt.Syntax
open Store
module Hash_set = Set.Make (String)

let rec get_first_parents repo commit =
  let parents = Store.Commit.parents commit in
  match parents with
  | [] -> Lwt.return [ `Commit (Store.Commit.key commit) ]
  | x ->
      let* x =
        Lwt_list.map_s
          (fun c ->
            let+ c = Store.Commit.of_key repo c in
            Option.get c)
          x
      in
      let+ p = Lwt_list.map_s (get_first_parents repo) x in
      List.flatten p

let gc { db; branch = current_branch } =
  let repo = Store.repo db in
  let* branches = Store.Branch.list repo in
  let info = Info.v "GC" () in
  let live = ref Hash_set.empty in
  let* max =
    Lwt_list.map_s
      (fun branch ->
        let* current = Store.Branch.get repo branch in
        match Store.Commit.parents current with
        | [] -> Lwt.return (`Commit (Store.Commit.key current))
        | _ ->
            let+ commit =
              if branch = current_branch then
                let* db = Store.of_branch repo branch in
                let* tree = Store.tree db in
                let* commit = Store.Commit.v repo ~info ~parents:[] tree in
                let+ () = Store.Branch.set repo branch commit in
                commit
              else Lwt.return current
            in
            `Commit (Store.Commit.key commit))
      branches
  in
  let* min =
    Lwt_list.map_s
      (fun branch ->
        let* commit = Store.Branch.get repo branch in
        get_first_parents repo commit)
      branches
  in
  let min = List.flatten min in
  let node key =
    let+ tree = Store.Tree.of_key repo (`Node key) in
    let tree = Option.get tree in
    live :=
      Hash_set.add
        (Irmin.Type.to_string Store.Hash.t @@ Store.Tree.hash tree)
        !live
  in
  let contents key =
    let+ c = Store.Contents.of_key repo key in
    let c = Option.get c in
    live :=
      Hash_set.add
        (Irmin.Type.to_string Store.Hash.t @@ Store.Contents.hash c)
        !live
  in
  let commit key =
    let+ c = Store.Commit.of_hash repo key in
    let c = Option.get c in
    live :=
      Hash_set.add
        (Irmin.Type.to_string Store.Hash.t @@ Store.Commit.hash c)
        !live
  in
  let* () = Store.Repo.iter ~min ~max ~node ~contents ~commit repo in
  let config = Store.Repo.config repo in
  let root = Irmin.Backend.Conf.get config Irmin_fs.Conf.Key.root in
  let objects = root // "objects" in
  let a = Lwt_unix.files_of_directory objects in
  let total = ref 0 in
  let* () =
    Lwt_stream.iter_p
      (fun path ->
        if path = "." || path = ".." then Lwt.return_unit
        else
          let b = Lwt_unix.files_of_directory (objects // path) in
          Lwt_stream.iter_s
            (fun f ->
              if f = "." || f = ".." then Lwt.return_unit
              else
                let hash = path ^ f in
                if not (Hash_set.mem hash !live) then
                  let* () = Lwt_unix.unlink (objects // path // f) in
                  let+ () =
                    Lwt.catch
                      (fun () -> Lwt_unix.rmdir (objects // path))
                      (fun _ -> Lwt.return_unit)
                  in
                  incr total
                else Lwt.return_unit)
            b)
      a
  in
  Lwt.return !total
