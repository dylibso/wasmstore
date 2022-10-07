open Lwt.Syntax
open Wasmstore
open Cmdliner

let default_root = Filename.concat (Sys.getenv "HOME") ".wasmstore"

let root =
  let doc = "root" in
  Arg.(value & opt string default_root & info [ "root" ] ~docv:"WASM" ~doc)

let file p =
  let doc = "file" in
  Arg.(value & pos p file "" & info [] ~docv:"WASM" ~doc)

let path p =
  let doc = "path" in
  Arg.(value & pos p (list ~sep:'/' string) [] & info [] ~docv:"PATH" ~doc)

let read_file filename = In_channel.with_open_bin filename In_channel.input_all

let add =
  let cmd root path filename =
    Lwt_main.run
      (let* t = v ~root in
       let+ hash = add t path (read_file filename) in
       Format.printf "%a\n" (Irmin.Type.pp Store.hash_t) hash)
  in
  let doc = "Add a WASM module" in
  let info = Cmd.info "add" ~doc in
  let term = Term.(const cmd $ root $ path 0 $ file 1) in
  Cmd.v info term

let find =
  let cmd root path =
    Lwt_main.run
      (let* t = v ~root in
       let+ value =
         match path with
         | [ maybe_hash ] -> (
             match Irmin.Type.of_string Store.hash_t maybe_hash with
             | Ok hash -> find_hash t hash
             | Error _ -> find t path)
         | _ -> find t path
       in
       match value with None -> exit 1 | Some value -> print_string value)
  in
  let doc = "Find a WASM module by hash or name" in
  let info = Cmd.info "find" ~doc in
  let term = Term.(const cmd $ root $ path 0) in
  Cmd.v info term

let remove =
  let cmd root path =
    Lwt_main.run
      (let* t = v ~root in
       remove t path)
  in
  let doc = "Remove WASM module from store by hash" in
  let info = Cmd.info "remove" ~doc in
  let term = Term.(const cmd $ root $ path 0) in
  Cmd.v info term

let gc =
  let cmd root =
    Unix.chdir root;
    let _ = Unix.system "git gc" in
    ()
  in
  let doc = "Remove modules that are no longer referenced" in
  let info = Cmd.info "gc" ~doc in
  let term = Term.(const cmd $ root) in
  Cmd.v info term

let list =
  let cmd root path =
    Lwt_main.run
      (let* t = v ~root in
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
  let term = Term.(const cmd $ root $ path 0) in
  Cmd.v info term

let commands = Cmd.group (Cmd.info "wasmstore") [ add; find; remove; gc; list ]
let main () = exit (Cmd.eval commands)
let () = main ()
