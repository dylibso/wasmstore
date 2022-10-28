(*
 * Copyright (c) 2013-2022 Thomas Gazagnaire <thomas@gazagnaire.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open! Irmin.Export_for_backends
open Astring

let src = Logs.Src.create "wasmstore.storage" ~doc:"wasmstore disk storage"

module Log = (val Logs.src_log src : Logs.LOG)

let ( / ) = Filename.concat

module type Config = sig
  val dir : string -> string
  val file_of_key : string -> string
  val key_of_file : string -> string
end

module Conf = struct
  include Irmin.Backend.Conf

  let spec = Spec.v "wasmstore"

  module Key = struct
    let root = root spec
  end
end

let config r = Conf.(verify (add (empty Conf.spec) Key.root r))

module Read_only_ext (S : Config) (K : Irmin.Type.S) (V : Irmin.Type.S) = struct
  type key = K.t
  type value = V.t
  type 'a t = { path : string }

  let get_path config = Option.value Conf.(find_root config) ~default:"."

  let v config =
    let path = get_path config in
    IO.mkdir path >|= fun () -> { path }

  let close _ = Lwt.return_unit
  let cast t = (t :> read_write t)
  let batch t f = f (cast t)

  let file_of_key { path; _ } key =
    path / S.file_of_key (Irmin.Type.to_string K.t key)

  let lock_of_key { path; _ } key =
    IO.lock_file (path / "lock" / S.file_of_key (Irmin.Type.to_string K.t key))

  let mem t key =
    let file = file_of_key t key in
    IO.file_exists file

  let of_bin_string = Irmin.Type.(unstage (of_bin_string V.t))

  let value v =
    match of_bin_string v with
    | Ok v -> Some v
    | Error (`Msg e) ->
        [%log.err "Irmin_fs.value %s" e];
        None

  let pp_key = Irmin.Type.pp K.t

  let find t key =
    [%log.debug "find %a" pp_key key];
    IO.read_file (file_of_key t key) >|= function
    | None -> None
    | Some x -> value x

  let list t =
    [%log.debug "list"];
    let+ files = IO.rec_files (S.dir t.path) in
    let files =
      let p = String.length t.path in
      List.fold_left
        (fun acc file ->
          let n = String.length file in
          if n <= p + 1 then acc
          else
            let file = String.with_range file ~first:(p + 1) in
            file :: acc)
        [] files
    in
    List.fold_left
      (fun acc file ->
        match Irmin.Type.of_string K.t (S.key_of_file file) with
        | Ok k -> k :: acc
        | Error (`Msg e) ->
            [%log.err "Irmin_fs.list: %s" e];
            acc)
      [] files
end

module Append_only_ext (S : Config) (K : Irmin.Type.S) (V : Irmin.Type.S) =
struct
  include Read_only_ext (S) (K) (V)

  let temp_dir t = t.path / "tmp"
  let to_bin_string = Irmin.Type.(unstage (to_bin_string V.t))

  let add t key value =
    [%log.debug "add %a" pp_key key];
    let file = file_of_key t key in
    let temp_dir = temp_dir t in
    IO.file_exists file >>= function
    | true -> Lwt.return_unit
    | false ->
        let str = to_bin_string value in
        IO.write_file ~temp_dir file str
end

module Atomic_write_ext (S : Config) (K : Irmin.Type.S) (V : Irmin.Type.S) =
struct
  module RO = Read_only_ext (S) (K) (V)
  module W = Irmin.Backend.Watch.Make (K) (V)

  type t = { t : unit RO.t; w : W.t }
  type key = RO.key
  type value = RO.value
  type watch = W.watch * (unit -> unit Lwt.t)

  let temp_dir t = t.t.RO.path / "tmp"

  module E = Ephemeron.K1.Make (struct
    type t = string

    let equal x y = compare x y = 0
    let hash = Hashtbl.hash
  end)

  let watches = E.create 10

  let v config =
    let+ t = RO.v config in
    let w =
      let path = RO.get_path config in
      try E.find watches path
      with Not_found ->
        let w = W.v () in
        E.add watches path w;
        w
    in
    { t; w }

  let close t = W.clear t.w >>= fun () -> RO.close t.t
  let find t = RO.find t.t
  let mem t = RO.mem t.t
  let list t = RO.list t.t

  let listen_dir t =
    let dir = S.dir t.t.RO.path in
    let key file =
      match Irmin.Type.of_string K.t file with
      | Ok t -> Some t
      | Error (`Msg e) ->
          [%log.err "listen_dir: %s" e];
          None
    in
    W.listen_dir t.w dir ~key ~value:(RO.find t.t)

  let watch_key t key ?init f =
    let* stop = listen_dir t in
    let+ w = W.watch_key t.w key ?init f in
    (w, stop)

  let watch t ?init f =
    let* stop = listen_dir t in
    let+ w = W.watch t.w ?init f in
    (w, stop)

  let unwatch t (id, stop) = stop () >>= fun () -> W.unwatch t.w id
  let raw_value = Irmin.Type.(unstage (to_bin_string V.t))

  let set t key value =
    [%log.debug "update %a" RO.pp_key key];
    let temp_dir = temp_dir t in
    let file = RO.file_of_key t.t key in
    let lock = RO.lock_of_key t.t key in
    IO.write_file ~temp_dir file ~lock (raw_value value) >>= fun () ->
    W.notify t.w key (Some value)

  let remove t key =
    [%log.debug "remove %a" RO.pp_key key];
    let file = RO.file_of_key t.t key in
    let lock = RO.lock_of_key t.t key in
    let* () = IO.remove_file ~lock file in
    W.notify t.w key None

  let test_and_set t key ~test ~set =
    [%log.debug "test_and_set %a" RO.pp_key key];
    let temp_dir = temp_dir t in
    let file = RO.file_of_key t.t key in
    let lock = RO.lock_of_key t.t key in
    let raw_value = function None -> None | Some v -> Some (raw_value v) in
    let* b =
      IO.test_and_set_file file ~temp_dir ~lock ~test:(raw_value test)
        ~set:(raw_value set)
    in
    let+ () = if b then W.notify t.w key set else Lwt.return_unit in
    b

  let clear t =
    [%log.debug "clear"];
    let remove_file key =
      IO.remove_file ~lock:(RO.lock_of_key t.t key) (RO.file_of_key t.t key)
    in
    list t >>= Lwt_list.iter_p remove_file
end

module Maker_ext (Obj : Config) (Ref : Config) = struct
  module AO = Append_only_ext (Obj)
  module AW = Atomic_write_ext (Ref)
  module CA = Irmin.Content_addressable.Make (AO)
  include Irmin.Maker (CA) (AW)
end

let string_chop_prefix ~prefix str =
  let len = String.length prefix in
  if String.length str <= len then "" else String.with_range str ~first:len

module Ref = struct
  let dir p = p / "refs"

  (* separator for branch names is '/', so need to rewrite the path on
     Windows. *)

  let file_of_key key =
    let file =
      if Sys.os_type <> "Win32" then key
      else String.concat ~sep:Filename.dir_sep (String.cuts ~sep:"/" key)
    in
    "refs" / file

  let key_of_file file =
    let key = string_chop_prefix ~prefix:("refs" / "") file in
    if Sys.os_type <> "Win32" then key
    else String.concat ~sep:"/" (String.cuts ~sep:Filename.dir_sep key)
end

module Obj = struct
  let dir t = t / "objects"

  let file_of_key k =
    let pre = String.with_range k ~len:2 in
    let suf = String.with_range k ~first:2 in
    "objects" / pre / suf

  let key_of_file path =
    let path = string_chop_prefix ~prefix:("objects" / "") path in
    let path = String.cuts ~sep:Filename.dir_sep path in
    let path = String.concat ~sep:"" path in
    path
end

module Append_only = Append_only_ext (Obj)
module Atomic_write = Atomic_write_ext (Ref)
module Maker = Maker_ext (Obj) (Ref)

module KV = struct
  module CA = Irmin.Content_addressable.Make (Append_only)
  include Irmin.KV_maker (CA) (Atomic_write)
end

module Store = Maker.Make (Schema)
