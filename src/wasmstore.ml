include Store
include Gc
module Branch = Branch
module Server = Server
module Error = Error

let watch = Diff.watch
let unwatch w = Lwt_eio.run_lwt @@ fun () -> Store.unwatch w
