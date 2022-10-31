open Lwt.Syntax

type t = [ `Msg of string | `Exception of exn ]
type 'a res = ('a, t) result

let to_string = function
  | `Msg s -> s
  | `Exception (Failure f) -> f
  | `Exception (Invalid_argument f) -> f
  | `Exception e -> Printexc.to_string e

exception Wasmstore of t

let () =
  Printexc.register_printer (function
    | Wasmstore error -> Some (to_string error)
    | _ -> None)

let handle_error f = function
  | Wasmstore error -> f error
  | e -> f (`Exception e)

let unwrap' = function Ok x -> x | Error e -> raise (Wasmstore e)
let wrap' f = try Ok (f ()) with e -> handle_error Result.error e

let unwrap x =
  let* x = x in
  Lwt.return (unwrap' x)

let wrap f =
  Lwt.catch
    (fun () ->
      let* x = f () in
      Lwt.return_ok x)
    (handle_error Lwt.return_error)

let throw e = raise (Wasmstore e)
let mk' f = try f () with e -> handle_error throw e
let mk f = Lwt.catch f (handle_error throw)
let catch' f g = try f () with e -> handle_error g e
let catch f g = Lwt.catch f (handle_error g)
