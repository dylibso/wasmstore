open Wasmstore

let weekday Unix.{ tm_wday; _ } =
  match tm_wday with
  | 0 -> "Sun"
  | 1 -> "Mon"
  | 2 -> "Tue"
  | 3 -> "Wed"
  | 4 -> "Thu"
  | 5 -> "Fri"
  | 6 -> "Sat"
  | _ -> assert false

let month Unix.{ tm_mon; _ } =
  match tm_mon with
  | 0 -> "Jan"
  | 1 -> "Feb"
  | 2 -> "Mar"
  | 3 -> "Apr"
  | 4 -> "May"
  | 5 -> "Jun"
  | 6 -> "Jul"
  | 7 -> "Aug"
  | 8 -> "Sep"
  | 9 -> "Oct"
  | 10 -> "Nov"
  | 11 -> "Dec"
  | _ -> assert false

let convert_date timestamp =
  let date = Unix.localtime (Int64.to_float timestamp) in
  Fmt.str "%s %s %02d %02d:%02d:%02d %04d" (weekday date) (month date)
    date.tm_mday date.tm_hour date.tm_min date.tm_sec (date.tm_year + 1900)

let run f =
  Eio_main.run @@ fun env ->
  Lwt_eio.with_event_loop ~clock:env#clock @@ fun _token ->
  Lwt_eio.run_lwt @@ fun () ->
  Error.catch_lwt
    (fun () -> f)
    (fun err -> Logs.err (fun l -> l "%s" (Error.to_string err)); Lwt.return_unit)
