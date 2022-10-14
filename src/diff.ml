open Lwt.Syntax
open Store

let update_old_new v v' =
  `Assoc
    [
      ( "old",
        `String (Irmin.Type.to_string Store.Hash.t (Store.Contents.hash v)) );
      ( "new",
        `String (Irmin.Type.to_string Store.Hash.t (Store.Contents.hash v')) );
    ]

let make_diff list =
  `Assoc
    (List.map
       (function
         | path, `Updated ((v, ()), (v', ())) ->
             let path = Irmin.Type.to_string Store.path_t path in
             ( path,
               `Assoc
                 [
                   ("action", `String "updated"); ("hash", update_old_new v v');
                 ] )
         | path, `Removed (v, ()) ->
             let path = Irmin.Type.to_string Store.path_t path in
             ( path,
               `Assoc
                 [
                   ("action", `String "added");
                   ( "hash",
                     `String
                       (Irmin.Type.to_string Store.Hash.t
                          (Store.Contents.hash v)) );
                 ] )
         | path, `Added (v, ()) ->
             let path = Irmin.Type.to_string Store.path_t path in
             ( path,
               `Assoc
                 [
                   ("action", `String "added");
                   ( "hash",
                     `String
                       (Irmin.Type.to_string Store.Hash.t
                          (Store.Contents.hash v)) );
                 ] ))
       list)

let json_of_diff t (diff : Store.commit Irmin.Diff.t) : Yojson.Safe.t Lwt.t =
  match diff with
  | `Updated (commit, commit') ->
      let tree = Store.Commit.tree commit in
      let tree' = Store.Commit.tree commit' in
      let+ list = Store.Tree.diff tree tree' in
      make_diff list
  | `Removed commit | `Added commit ->
      let tree = Store.Commit.tree commit in
      let parents = Store.Commit.parents commit in
      let+ changes =
        Lwt_list.filter_map_s
          (fun parent ->
            let* commit = Store.Commit.of_key (repo t) parent in
            match commit with
            | None -> Lwt.return_none
            | Some commit ->
                let* x = Store.Tree.diff (Store.Commit.tree commit) tree in
                Lwt.return_some x)
          parents
      in
      let changes = List.flatten changes in
      make_diff changes

let string_of_diff t d =
  let+ j = json_of_diff t d in
  Yojson.Safe.to_string j

let watch t f =
  Store.watch t.db (fun diff ->
      let* j = json_of_diff t diff in
      f j)
