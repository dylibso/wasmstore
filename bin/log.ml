open Lwt.Syntax
open Wasmstore
open Cmdliner
open Util

let log store =
  let plain =
    let doc = Arg.info ~doc:"Show plain text without pager" [ "plain" ] in
    Arg.(value & flag & doc)
  in
  let pager =
    let doc = Arg.info ~doc:"Specify pager program to use" [ "pager" ] in
    Arg.(value & opt string "pager" & doc)
  in
  let num =
    let doc = Arg.info ~doc:"Number of entries to show" [ "n"; "max-count" ] in
    Arg.(value & opt (some int) None & doc)
  in
  let skip =
    let doc = Arg.info ~doc:"Number of entries to skip" [ "skip" ] in
    Arg.(value & opt (some int) None & doc)
  in
  let reverse =
    let doc = Arg.info ~doc:"Print in reverse order" [ "reverse" ] in
    Arg.(value & flag & doc)
  in
  let exception Return in
  let cmd store plain pager num skip reverse =
    run @@ fun env ->
    let t = store env in
    let repo = repo t in
    let skip = ref (Option.value ~default:0 skip) in
    let num = Option.value ~default:0 num in
    let num_count = ref 0 in
    let commit formatter key =
      if num > 0 && !num_count >= num then raise Return
      else if !skip > 0 then
        let () = decr skip in
        Lwt.return_unit
      else
        let+ commit = Store.Commit.of_key repo key in
        let hash = Store.Backend.Commit.Key.to_hash key in
        let info = Store.Commit.info (Option.get commit) in
        let date = Store.Info.date info in
        let author = Store.Info.author info in
        let message = Store.Info.message info in
        let () =
          Fmt.pf formatter "commit %a\nAuthor: %s\nDate: %s\n\n%s\n\n%!"
            (Irmin.Type.pp Store.hash_t)
            hash author (convert_date date) message
        in
        incr num_count
    in
    let* x = Store.Head.get (Wasmstore.store t) in
    let max = [ `Commit (Store.Commit.key x) ] in
    let iter ~commit ~max repo =
      Lwt.catch
        (fun () ->
          if reverse then Store.Repo.iter ~commit ~min:[] ~max repo
          else Store.Repo.breadth_first_traversal ~commit ~max repo)
        (function Return -> Lwt.return_unit | exn -> raise exn)
    in
    if plain then
      let commit = commit Format.std_formatter in
      iter ~commit ~max repo
    else
      Lwt.catch
        (fun () ->
          let out = Unix.open_process_out pager in
          let commit = commit (Format.formatter_of_out_channel out) in
          let+ () = iter ~commit ~max repo in
          let _ = Unix.close_process_out out in
          ())
        (function
          | Sys_error s when String.equal s "Broken pipe" -> Lwt.return_unit
          | exn -> raise exn)
  in
  let doc = "list all commits in order" in
  let info = Cmd.info "log" ~doc in
  let term = Term.(const cmd $ store $ plain $ pager $ num $ skip $ reverse) in
  Cmd.v info term
