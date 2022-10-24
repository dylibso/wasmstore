open Lwt.Syntax
open Store
open Gc
open Diff
open Cohttp
open Cohttp_lwt
open Cohttp_lwt_unix

let () = Irmin.Backend.Watch.set_listen_dir_hook Irmin_watcher.hook

let with_branch' t req =
  let h = Cohttp.Request.headers req in
  let branch = Cohttp.Header.get h "Wasmstore-Branch" in
  match branch with None -> Lwt.return t | Some branch -> with_branch t branch

let response x =
  let+ x = x in
  `Response x

let list_modules t ~headers req path =
  let* t = with_branch' t req in
  let* modules = list t path in
  let modules =
    List.map
      (fun (k, v) ->
        ( Irmin.Type.to_string Store.Path.t k,
          `String (Irmin.Type.to_string Store.Hash.t v) ))
      modules
  in
  let body = Yojson.Safe.to_string (`Assoc modules) in
  response @@ Server.respond_string ~status:`OK ~headers ~body ()

let list_branches t ~headers =
  let* branches = Branch.list t in
  let body =
    Body.of_string (Irmin.Type.(to_json_string (list string)) branches)
  in
  response @@ Server.respond ~headers ~body ~status:`OK ()

let add_module t ~headers req body path =
  let* t = with_branch' t req in
  let* data = Body.to_string body in
  Lwt.catch
    (fun () ->
      let* hash = add t path data in
      let body = Irmin.Type.to_string Store.Hash.t hash in
      response @@ Server.respond_string ~headers ~status:`OK ~body ())
    (function
      | Wasm.Valid.Invalid (region, msg) | Wasm.Decode.Code (region, msg) ->
          let s =
            Printf.sprintf "%s: %s" (Wasm.Source.string_of_region region) msg
          in
          response
          @@ Server.respond_string ~headers ~status:`Bad_request ~body:s ()
      | exn -> raise exn)

let remove_prefix path =
  match path with "api" :: "v1" :: tl -> Some (`V1 tl) | _ -> None

let require_auth ~body ~auth ~headers req ~v1 =
  let uri = Request.uri req in
  let meth = Request.meth req in
  let path = Uri.path uri in
  let path' =
    String.split_on_char '/' path
    |> List.filter_map (function "" -> None | x -> Some x)
  in
  let path' = remove_prefix path' in
  Logs.info (fun l ->
      l "%s %s\n%s"
        (Code.string_of_method meth)
        path
        (Request.headers req |> Header.to_string |> String.trim));
  let f () =
    match path' with
    | Some p -> v1 (meth, p)
    | None ->
        let* () = Body.drain_body body in
        response
        @@ Server.respond_string ~headers ~status:`Not_found ~body:"" ()
  in
  if Hashtbl.length auth = 0 then f ()
  else
    let h = Request.headers req in
    let key = Header.get h "Wasmstore-Auth" |> Option.value ~default:"" in
    let perms =
      Hashtbl.find_opt auth key |> Option.map (String.split_on_char ',')
    in
    match perms with
    | Some [ "*" ] -> f ()
    | Some x ->
        let exists =
          List.exists
            (fun m -> String.equal (Cohttp.Code.string_of_method meth) m)
            x
        in
        if exists then f ()
        else
          response
          @@ Server.respond_string ~headers ~status:`Unauthorized ~body:"" ()
    | None ->
        response
        @@ Server.respond_string ~headers ~status:`Unauthorized ~body:"" ()

let find_module t ~headers req path =
  let* t = with_branch' t req in
  let* filename = get_hash_and_filename t path in
  match filename with
  | Some (hash, filename) ->
      let headers =
        Header.add headers "Wasmstore-Hash"
          (Irmin.Type.to_string Store.Hash.t hash)
      in
      response @@ Server.respond_file ~headers ~fname:(root t // filename) ()
  | _ ->
      response @@ Server.respond_string ~headers ~status:`Not_found ~body:"" ()

let delete_module t ~headers req path =
  let* t = with_branch' t req in
  let* () = remove t path in
  response @@ Server.respond_string ~headers ~status:`OK ~body:"" ()

let find_hash t ~headers req path =
  let* t = with_branch' t req in
  let* hash = hash t path in
  match hash with
  | Some hash ->
      let body = Body.of_string (Irmin.Type.to_string Store.Hash.t hash) in
      response @@ Server.respond ~headers ~status:`OK ~body ()
  | None ->
      response @@ Server.respond_string ~headers ~status:`Not_found ~body:"" ()

let callback t ~headers ~auth _conn req body =
  require_auth ~auth ~headers ~body req ~v1:(function
    | `GET, `V1 ("modules" :: path) ->
        let* () = Body.drain_body body in
        list_modules t ~headers req path
    | `GET, `V1 ("module" :: path) ->
        let* () = Body.drain_body body in
        find_module t ~headers req path
    | `GET, `V1 ("hash" :: path) ->
        let* () = Body.drain_body body in
        find_hash t ~headers req path
    | `POST, `V1 ("module" :: path) -> add_module t ~headers req body path
    | `DELETE, `V1 ("module" :: path) ->
        let* () = Body.drain_body body in
        delete_module t ~headers req path
    | `POST, `V1 [ "gc" ] ->
        let* () = Body.drain_body body in
        let* t = with_branch' t req in
        let* _ = gc t in
        response @@ Server.respond_string ~headers ~status:`OK ~body:"" ()
    | `POST, `V1 [ "merge"; from_branch ] -> (
        let* t = with_branch' t req in
        let* res = merge t from_branch in
        match res with
        | Ok _ ->
            response @@ Server.respond_string ~status:`OK ~headers ~body:"" ()
        | Error r ->
            response
            @@ Server.respond_string ~headers ~status:`Bad_request
                 ~body:(Irmin.Type.to_string Irmin.Merge.conflict_t r)
                 ())
    | `POST, `V1 [ "restore"; hash ] -> (
        let* t = with_branch' t req in
        let hash = Irmin.Type.of_string Store.Hash.t hash in
        match hash with
        | Error _ ->
            response
            @@ Server.respond_string ~headers ~status:`Bad_request
                 ~body:"invalid hash in request" ()
        | Ok hash -> (
            let* commit = Store.Commit.of_hash (repo t) hash in
            match commit with
            | None ->
                response
                @@ Server.respond_string ~headers ~status:`Not_found
                     ~body:"commit not found" ()
            | Some commit ->
                let* () = restore t commit in
                response
                @@ Server.respond_string ~headers ~status:`OK ~body:"" ()))
    | `GET, `V1 [ "snapshot" ] ->
        let* t = with_branch' t req in
        let* commit = snapshot t in
        response
        @@ Server.respond_string ~headers ~status:`OK
             ~body:
               (Irmin.Type.to_string Store.Hash.t (Store.Commit.hash commit))
             ()
    | `GET, `V1 [ "branches" ] ->
        let* () = Body.drain_body body in
        list_branches t ~headers
    | `PUT, `V1 [ "branch"; branch ] ->
        let* () = Branch.switch t branch in
        response @@ Server.respond_string ~headers ~body:"" ~status:`OK ()
    | `POST, `V1 [ "branch"; branch ] -> (
        let* res = Branch.create t branch in
        match res with
        | Ok _ ->
            response @@ Server.respond_string ~headers ~status:`OK ~body:"" ()
        | Error (`Msg s) ->
            response
            @@ Server.respond_string ~headers ~status:`Conflict ~body:s ())
    | `DELETE, `V1 [ "branch"; branch ] ->
        let* () = Branch.delete t branch in
        response @@ Server.respond_string ~headers ~body:"" ~status:`OK ()
    | `GET, `V1 [ "branch" ] ->
        response @@ Server.respond_string ~headers ~status:`OK ~body:t.branch ()
    | `GET, `V1 [ "watch" ] ->
        let w = ref None in
        let* a, send =
          Server_websocket.upgrade_connection req (fun msg ->
              if msg.opcode = Websocket.Frame.Opcode.Close then
                match !w with
                | Some w -> Lwt.async (fun () -> Store.unwatch w)
                | None -> ())
        in
        let+ watch =
          watch t (fun diff ->
              Lwt.catch
                (fun () ->
                  let d = Yojson.Safe.to_string diff in
                  Lwt.wrap (fun () ->
                      send (Some (Websocket.Frame.create ~content:d ()))))
                (fun _ ->
                  match !w with
                  | Some w' ->
                      let+ () = Store.unwatch w' in
                      w := None
                  | None -> Lwt.return_unit))
        in
        w := Some watch;
        a
    | _ ->
        let* () = Body.drain_body body in
        response
        @@ Server.respond_string ~headers ~body:"" ~status:`Not_found ())

let run ?tls ?(cors = false) ?auth ?(host = "localhost") ?(port = 6384) t =
  let headers =
    if cors then Header.of_list [ ("Access-Control-Allow-Origin", "*") ]
    else Header.of_list []
  in
  let auth : (string, string) Hashtbl.t =
    match auth with
    | Some x -> Hashtbl.of_seq (List.to_seq x)
    | None -> Hashtbl.create 0
  in
  let mode, tls_own_key =
    match tls with
    | Some (`Key_file kf, `Cert_file cf) ->
        let cert = `Crt_file_path cf in
        let key = `Key_file_path kf in
        ( `TLS (cert, key, `No_password, `Port port),
          Some (`TLS (cert, key, `No_password)) )
    | None -> (`TCP (`Port port), None)
  in
  let* ctx = Conduit_lwt_unix.init ~src:host ?tls_own_key () in
  let ctx = Net.init ~ctx () in
  let callback = callback t ~headers ~auth in
  let server = Server.make_response_action ~callback () in
  Logs.app (fun l ->
      l "Starting server on %s:%d, cors=%b, tls=%b" host port cors
        (Option.is_some tls));
  Server.create ~ctx ~on_exn:(fun _ -> ()) ~mode server
