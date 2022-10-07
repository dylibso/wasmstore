module Store :
  Irmin_git_unix.S
    with type Schema.Contents.t = string
     and type Schema.Path.t = string list

type t
type hash = Store.Hash.t

val v : root:string -> t Lwt.t
val add : t -> string list -> string -> hash Lwt.t
val find_hash : t -> hash -> string option Lwt.t
val find : t -> string list -> string option Lwt.t
val remove : t -> string list -> unit Lwt.t
val list : t -> string list -> (string list * hash) list Lwt.t
