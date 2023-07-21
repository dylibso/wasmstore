let ( let$ ) x f = f @@ Lwt_eio.run_lwt @@ fun () -> x
let ( let^ ) x f = f @@ Lwt_eio.run_eio @@ fun () -> x
