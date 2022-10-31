open Lwt.Syntax
open Wasmstore
open Cmdliner
open Util

let reporter ppf =
  let report src level ~over k msgf =
    let k _ =
      over ();
      k ()
    in
    let with_metadata header _tags k ppf fmt =
      Format.kfprintf k ppf
        ("%a[%a]: " ^^ fmt ^^ "\n%!")
        Logs_fmt.pp_header (level, header)
        Fmt.(styled `Magenta string)
        (Logs.Src.name src)
    in
    msgf @@ fun ?header ?tags fmt -> with_metadata header tags k ppf fmt
  in
  { Logs.report }

let setup_log style_renderer level =
  Fmt_tty.setup_std_outputs ?style_renderer ();
  Logs.set_level ~all:true level;
  Logs.set_reporter (reporter Fmt.stderr);
  ()

let setup_log =
  Term.(const setup_log $ Fmt_cli.style_renderer () $ Logs_cli.level ())

let default_root = Filename.concat (Sys.getenv "HOME") ".wasmstore"

let root =
  let doc = "root" in
  let env = Cmd.Env.info "WASMSTORE_ROOT" in
  Arg.(value & opt string default_root & info [ "root" ] ~docv:"PATH" ~doc ~env)

let branch =
  let doc = "branch" in
  let env = Cmd.Env.info "WASMSTORE_BRANCH" in
  Arg.(
    value
    & opt string Store.Branch.main
    & info [ "branch" ] ~docv:"NAME" ~doc ~env)

let author =
  let doc = "author" in
  let env = Cmd.Env.info "WASMSTORE_AUTHOR" in
  Arg.(
    value & opt (some string) None & info [ "author" ] ~docv:"NAME" ~doc ~env)

let tls =
  let doc = "tls key file and certificate file" in
  let env = Cmd.Env.info "WASMSTORE_TLS" in
  Arg.(
    value
    & opt (some (pair ~sep:',' string string)) None
    & info [ "tls" ] ~docv:"KEY_FILE,CERT_FILE" ~doc ~env)

let host =
  let doc = "hostname" in
  let env = Cmd.Env.info "WASMSTORE_HOST" in
  Arg.(value & opt (some string) None & info [ "host" ] ~docv:"HOST" ~doc ~env)

let port =
  let doc = "port" in
  let env = Cmd.Env.info "WASMSTORE_PORT" in
  Arg.(value & opt (some int) None & info [ "port" ] ~docv:"PORT" ~doc ~env)

let branch_from n =
  let doc = "branch to merge from" in
  Arg.(value & pos n string Store.Branch.main & info [] ~docv:"NAME" ~doc)

let branch_name n =
  let doc = "branch name" in
  Arg.(value & pos n string Store.Branch.main & info [] ~docv:"NAME" ~doc)

let hash n =
  let doc = "hash" in
  Arg.(value & pos n string "" & info [] ~docv:"HASH" ~doc)

let delete_flag =
  let doc = "delete branch" in
  Arg.(value & flag & info [ "delete" ] ~doc)

let list_flag =
  let doc = "list branches" in
  Arg.(value & flag & info [ "list" ] ~doc)

let file p =
  let doc = "file" in
  Arg.(value & pos p string "" & info [] ~docv:"WASM" ~doc)

let path p =
  let doc = "path" in
  Arg.(value & pos p (list ~sep:'/' string) [] & info [] ~docv:"PATH" ~doc)

let path_opt p =
  let doc = "path" in
  Arg.(
    value & pos p (some (list ~sep:'/' string)) None & info [] ~docv:"PATH" ~doc)

let auth =
  let doc = "auth" in
  let env = Cmd.Env.info "WASMSTORE_AUTH" in
  Arg.(
    value
    & opt (some (list ~sep:';' (pair ~sep:':' string string))) None
    & info ~env [ "auth" ] ~docv:"KEY:GET,POST;KEY1:GET" ~doc)

let cors =
  let doc = "enable CORS" in
  Arg.(value & flag & info [ "cors" ] ~doc)

let store =
  let aux () root branch author = v ?author ~branch root in
  Term.(const aux $ setup_log $ root $ branch $ author)

let buf_size = 4096 * 2

let rec read_file buf ic f =
  let* n = Lwt_io.read_into ic buf 0 buf_size in
  f (Some (Bytes.sub_string buf 0 n));
  if n < buf_size then
    let () = f None in
    Lwt.return_unit
  else read_file buf ic f

let file_stream filename =
  let buf = Bytes.create buf_size in
  let s, push = Lwt_stream.create () in
  let* () =
    Lwt_io.with_file ~mode:Input filename (fun ic -> read_file buf ic push)
  in
  Lwt.return s

let stdin_stream () =
  let buf = Bytes.create buf_size in
  let s, push = Lwt_stream.create () in
  let* () = read_file buf Lwt_io.stdin push in
  Lwt.return s

let add =
  let cmd store filename path =
    let path =
      match path with Some p -> p | None -> [ Filename.basename filename ]
    in
    run
      (let* t = store in
       let* data =
         if filename = "-" then stdin_stream () else file_stream filename
       in
       Lwt.catch
         (fun () ->
           let+ hash = import t path data in
           Format.printf "%a\n" (Irmin.Type.pp Store.hash_t) hash)
         (function
           | Validation_error msg ->
               Lwt_io.fprintlf Lwt_io.stderr "ERROR invalid module: %s" msg
           | exn -> raise exn))
  in

  let doc = "Add a WASM module" in
  let info = Cmd.info "add" ~doc in
  let term = Term.(const cmd $ store $ file 0 $ path_opt 1) in
  Cmd.v info term

let find =
  let cmd store path =
    run
      (let* t = store in
       let+ value = find t path in
       match value with None -> exit 1 | Some value -> print_string value)
  in
  let doc = "Find a WASM module by hash or name" in
  let info = Cmd.info "find" ~doc in
  let term = Term.(const cmd $ store $ path 0) in
  Cmd.v info term

let remove =
  let cmd store path =
    run
      (let* t = store in
       Wasmstore.remove t path)
  in
  let doc = "Remove WASM module from store by hash" in
  let info = Cmd.info "remove" ~doc in
  let term = Term.(const cmd $ store $ path 0) in
  Cmd.v info term

let merge =
  let cmd store branch_from =
    run
      (let* t = store in
       let+ res = merge t branch_from in
       match res with
       | Ok () -> ()
       | Error e ->
           let stderr = Format.formatter_of_out_channel stderr in
           Format.fprintf stderr "ERROR: %a"
             (Irmin.Type.pp Irmin.Merge.conflict_t)
             e)
  in
  let doc = "Merge branch into main" in
  let info = Cmd.info "merge" ~doc in
  let term = Term.(const cmd $ store $ branch_from 0) in
  Cmd.v info term

let gc =
  let cmd store =
    run
      (let* t = store in
       let+ res = gc t in
       Printf.printf "%d\n" res)
  in
  let doc = "Cleanup modules that are no longer referenced" in
  let info = Cmd.info "gc" ~doc in
  let term = Term.(const cmd $ store) in
  Cmd.v info term

let list =
  let cmd store path =
    run
      (let* t = store in
       let+ items = list t path in
       List.iter
         (fun (path, hash) ->
           Format.printf "%a\t%a\n"
             (Irmin.Type.pp Store.Hash.t)
             hash
             (Irmin.Type.pp Store.Path.t)
             path)
         items)
  in
  let doc = "List WASM modules" in
  let info = Cmd.info "list" ~doc in
  let term = Term.(const cmd $ store $ path 0) in
  Cmd.v info term

let snapshot =
  let cmd store =
    run
      (let* t = store in
       let+ head = snapshot t in
       print_endline
         (Irmin.Type.to_string Store.Hash.t (Store.Commit.hash head)))
  in
  let doc = "Get current head commit hash" in
  let info = Cmd.info "snapshot" ~doc in
  let term = Term.(const cmd $ store) in
  Cmd.v info term

let restore =
  let cmd store commit path =
    run
      (let* t = store in
       let hash = Irmin.Type.of_string Store.Hash.t commit in
       match hash with
       | Error _ ->
           Printf.fprintf stderr "Invalid hash\n";
           Lwt.return_unit
       | Ok hash -> (
           let* commit = Store.Commit.of_hash (repo t) hash in
           match commit with
           | None ->
               Printf.fprintf stderr "Invalid commit\n";
               Lwt.return_unit
           | Some commit -> restore ?path t commit))
  in
  let doc = "restore to a previous commit" in
  let info = Cmd.info "restore" ~doc in
  let term = Term.(const cmd $ store $ hash 0 $ path_opt 1) in
  Cmd.v info term

let rollback =
  let cmd store path =
    run
      (let* t = store in
       rollback ?path t ())
  in
  let doc = "rollback to the last commit" in
  let info = Cmd.info "rollback" ~doc in
  let term = Term.(const cmd $ store $ path_opt 0) in
  Cmd.v info term

let contains =
  let cmd store path =
    run
      (let* t = store in
       let+ value = contains t path in
       Format.printf "%b\n" value)
  in
  let doc = "Check if a WASM module exists by hash or name" in
  let info = Cmd.info "contains" ~doc in
  let term = Term.(const cmd $ store $ path 0) in
  Cmd.v info term

let hash =
  let cmd store path =
    run
      (let* t = store in
       let+ hash = Wasmstore.hash t path in
       match hash with
       | None -> exit 1
       | Some hash -> Format.printf "%a\n" (Irmin.Type.pp Store.Hash.t) hash)
  in
  let doc = "Get the hash for the provided path" in
  let info = Cmd.info "hash" ~doc in
  let term = Term.(const cmd $ store $ path 0) in
  Cmd.v info term

let server =
  let rec cmd store host port auth cors tls =
    let tls' =
      match tls with
      | Some (k, c) -> Some (`Key_file k, `Cert_file c)
      | None -> None
    in
    let* t = store in
    try Server.run ~cors ?tls:tls' ?host ?port ?auth t
    with _ -> cmd store host port auth cors tls
  in
  let cmd store host port auth cors tls =
    run (cmd store host port auth cors tls)
  in
  let doc = "Run server" in
  let info = Cmd.info "server" ~doc in
  let term = Term.(const cmd $ store $ host $ port $ auth $ cors $ tls) in
  Cmd.v info term

let branch =
  let cmd () root branch_name delete list =
    run
      (let* t = v root in
       if list then
         let+ branches = Branch.list t in
         List.iter print_endline branches
       else if delete then Branch.delete t branch_name
       else
         let* _ = Error.unwrap @@ Branch.create t branch_name in
         Lwt.return_unit)
  in
  let doc = "Modify a branch" in
  let info = Cmd.info "branch" ~doc in
  let term =
    Term.(
      const cmd $ setup_log $ root $ branch_name 0 $ delete_flag $ list_flag)
  in
  Cmd.v info term

let run_command command diff =
  match command with
  | h :: t ->
      let s = Yojson.Safe.to_string diff in
      Lwt_process.pwrite (h, Array.of_list (h :: t)) s
  | [] -> Lwt_io.printlf "%s" (Yojson.Safe.to_string diff)

let watch =
  let cmd store command =
    run
      (let* t = store in
       let* _w = watch t (run_command command) in
       let t, _ = Lwt.task () in
       t)
  in
  let doc = "Print updates or run command when the store is updated" in
  let info = Cmd.info "watch" ~doc in
  let command =
    let doc = Arg.info ~docv:"COMMAND" ~doc:"Command to execute" [] in
    Arg.(value & pos_all string [] & doc)
  in
  let term = Term.(const cmd $ store $ command) in
  Cmd.v info term

let audit =
  let cmd store path =
    run
      (let* t = store in
       let* lm = Store.last_modified (Wasmstore.store t) path in
       let* () =
         Lwt_list.iter_s
           (fun commit ->
             let info = Store.Commit.info commit in
             let hash = Store.Commit.hash commit in
             Lwt_io.printlf "%s\t%s\t%s"
               (convert_date @@ Store.Info.date info)
               (Store.Info.author info)
               (Irmin.Type.to_string Hash.t hash))
           lm
       in
       Lwt.return_unit)
  in
  let doc = "list commits that modified a specific path" in
  let info = Cmd.info "audit" ~doc in
  let term = Term.(const cmd $ store $ path 0) in
  Cmd.v info term

let versions =
  let cmd store path =
    run
      (let* t = store in
       let* versions = versions t path in
       List.iter
         (fun (k, `Commit v) ->
           Fmt.pr "%a\tcommit: %a\n" (Irmin.Type.pp Hash.t) k
             (Irmin.Type.pp Hash.t) v)
         versions;
       Lwt.return_unit)
  in
  let doc = "list previous versions of a path" in
  let info = Cmd.info "versions" ~doc in
  let term = Term.(const cmd $ store $ path 0) in
  Cmd.v info term

let commands =
  Cmd.group (Cmd.info "wasmstore")
    [
      add;
      find;
      remove;
      gc;
      list;
      contains;
      server;
      merge;
      branch;
      snapshot;
      restore;
      rollback;
      hash;
      watch;
      audit;
      versions;
      Log.log store;
    ]

let () = exit (Cmd.eval commands)
