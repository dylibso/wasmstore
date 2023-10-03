include Store
include Gc
module Branch = Branch
module Server = Server
module Error = Error

let watch = Diff.watch
let unwatch = Diff.unwatch
