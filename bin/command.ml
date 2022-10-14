open Lwt.Syntax

let run_command diff command proc =
  let simple_output diff = Lwt_io.printlf "%s" (Yojson.Safe.to_string diff) in
  (* Check if there was a command passed, if not print a simple message to stdout, if there is
     a command pass the whole diff *)
  match command with
  | h :: t ->
      let s = Yojson.Safe.to_string diff in
      let make_proc () =
        (* Start new process *)
        let p = Lwt_process.open_process_out (h, Array.of_list (h :: t)) in
        proc := Some p;
        p
      in
      let proc =
        (* Check if process is already running, if not run it *)
        match !proc with
        | None -> make_proc ()
        | Some p -> (
            (* Determine if the subprocess completed succesfully or exited with an error,
               if it was successful then we can restart it, otherwise report the exit code
               the user *)
            let status = p#state in
            match status with
            | Lwt_process.Running -> p
            | Exited (Unix.WEXITED 0) -> make_proc ()
            | Exited (Unix.WEXITED code) ->
                Printf.printf "Subprocess exited with code %d\n" code;
                exit code
            | Exited (Unix.WSIGNALED code) | Exited (Unix.WSTOPPED code) ->
                Printf.printf "Subprocess stopped with code %d\n" code;
                exit code)
      in
      (* Write the diff to the subprocess *)
      let* () = Lwt_io.write_line proc#stdin s in
      Lwt_io.flush proc#stdin
  | [] -> simple_output diff
