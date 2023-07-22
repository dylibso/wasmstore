let ( let$ ) x f = f @@ Lwt_eio.run_lwt @@ fun () -> x
let ( let^ ) x f = f @@ Lwt_eio.run_eio @@ fun () -> x
let lwt x = Lwt_eio.run_lwt x
