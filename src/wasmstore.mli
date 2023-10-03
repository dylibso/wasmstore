(** [Wasmstore] is a database used to securely store WebAssembly modules *)

(** The underlying irmin store *)
module Store :
  Irmin.S
    with type Schema.Contents.t = string
     and type Schema.Path.t = string list
     and type Schema.Branch.t = string
     and type hash = Irmin.Hash.SHA256.t
     and module Schema.Info = Irmin.Info.Default

exception Validation_error of string

(** Error type and convenience functions *)

module Error : sig
  type t = [ `Msg of string | `Exception of exn ]
  type 'a res = ('a, t) result

  exception Wasmstore of t

  val to_string : t -> string
  val unwrap : ('a, t) result -> 'a
  val unwrap_lwt : ('a, t) result Lwt.t -> 'a Lwt.t
  val wrap : (unit -> 'a) -> ('a, t) result
  val wrap_lwt : (unit -> 'a Lwt.t) -> ('a, t) result Lwt.t
  val throw : t -> 'a
  val catch_lwt : (unit -> 'a Lwt.t) -> (t -> 'a Lwt.t) -> 'a Lwt.t
  val catch : (unit -> 'a) -> (t -> 'a) -> 'a
end

type t
(** The main [Wasmstore] type *)

type hash = Irmin.Hash.SHA256.t
(** Hash type, SHA256 *)

module Hash : Irmin.Hash.S with type t = hash
(** Re-export of [Store.Hash] *)

val branch : t -> string
(** [branch t] returns the current branch *)

val store : t -> Store.t
(** [store t] returns the underlying irmin store *)

val repo : t -> Store.repo
(** [repo t] returns the underlying irmin repo *)

val v :
  ?author:string -> ?branch:string -> string -> env:Eio_unix.Stdenv.base -> t
(** [v ~branch root] opens a store open to [branch] on disk at [root] *)

val snapshot : t -> Store.commit
(** [snapshot t] gets the current head commit *)

val restore : t -> ?path:string list -> Store.commit -> unit
(** [restore t commit] sets the head commit, if [path] is provided then only the
    specfied path will be reverted *)

val rollback : t -> ?path:string list -> int -> unit
(** [rollback t n] sets the head commit to [n] commits in the past, if [path] is
    provided then only the specfied path will be reverted *)

val find : t -> string list -> string option
(** [find t path] returns the module associated with [path], if path is a
    single-item list containing the string representation of the hash then the
    module will be located using the hash instead. This goes for all functions
    that accept [path] arguments unless otherwise noted. *)

val add : t -> string list -> string -> hash
(** [add t path wasm_module] sets [path] to [wasm_module] after verifying the
    module. If [path] is a hash then it will be converted to "[$HASH].wasm". *)

val set : t -> string list -> hash -> unit
(** [set t path hash] sets [path] to an existing [hash] *)

val import : t -> string list -> string Lwt_stream.t -> hash
(** [import t path stream] adds a WebAssembly module from the given stream *)

val hash : t -> string list -> hash option
(** [hash t path] returns the hash associated the the value stored at [path], if
    it exists *)

val remove : t -> string list -> unit
(** [remove t path] deletes [path] *)

val list : t -> string list -> (string list * hash) list Lwt.t
(** [list t path] returns a list of modules stored under [path]. This function
    does not accept a hash parameter in place of [path] *)

val contains : t -> string list -> bool Lwt.t
(** [contains t path] returns true if [path] exists *)

val gc : t -> int Lwt.t
(** [gc t] runs the GC and returns the number of objects deleted.

    When the gc is executed for a branch all prior commits are squashed into one
    and all non-reachable objects are removed. For example, if an object is
    still reachable from another branch it will not be deleted. Because of this,
    running the garbage collector may purge prior commits, potentially causing
    `restore` to fail. *)

val get_hash_and_filename : t -> string list -> (hash * string) option Lwt.t
(** [get_hash_and_filename t path] returns a tuple containing the hash and the
    filename of the object disk relative to the root path *)

val merge : t -> string -> (unit, Irmin.Merge.conflict) result Lwt.t
(** [merge t branch] merges [branch] into [t] *)

val with_branch : t -> string -> t
(** [with_branch t branch] returns a copy of [t] with [branch] selected *)

val with_author : t -> string -> t
(** [with_author t name] returns a copy of [t] with [name] as the current author *)

val watch : t -> (Yojson.Safe.t -> unit Lwt.t) -> Store.watch Lwt.t
(** [watch t f] creates a new watch that calls [f] for each new commit *)

val unwatch : Store.watch -> unit Lwt.t
(** [unwatch w] unregisters and disables the watch [w] *)

val versions : t -> string list -> (hash * [ `Commit of hash ]) list Lwt.t

val version :
  t -> string list -> int -> (hash * [ `Commit of hash ]) option Lwt.t

module Commit_info : sig
  type t = {
    hash : Hash.t;
    parents : Hash.t list;
    author : string;
    date : int64;
    message : string;
  }
  [@@deriving irmin]
end

val commit_info : t -> hash -> Commit_info.t option Lwt.t

module Branch : sig
  val switch : t -> string -> unit Lwt.t
  (** [switch t branch] sets [t]'s branch to [branch] *)

  val create : t -> string -> t Error.res Lwt.t
  (** [create t branch] creates a new branch, returning an error result if the
      branch already exists *)

  val delete : t -> string -> unit Lwt.t
  (** [delete t branch] destroys [branch] *)

  val list : t -> string list Lwt.t
  (** [list t] returns a list of all branches *)
end

module Server : sig
  val run :
    ?tls:[ `Key_file of string ] * [ `Cert_file of string ] ->
    ?cors:bool ->
    ?auth:(string * string) list ->
    ?host:string ->
    ?port:int ->
    t ->
    unit Lwt.t
  (** [run ~cors ~auth ~host ~port t] starts the server on [host:port] If [auth]
      is empty then no authentication is required, otherwise the client should
      provide a key using the [Wasmstore-Auth] header. [auth] is a mapping from
      authentication keys to allowed request methods (or [*] as a shortcut for
      any method). The `cors` parameters will enable CORS when set to true,
      allowing for browser-based Javascript clients to make requests agains the
      database.

      Additionally, the [Wasmstore-Branch] header can used to determine which
      branch to access on any non-[/branch] endpoints *)
end
