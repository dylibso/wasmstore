open Lwt.Syntax
open Store
open Gc
open Diff

let () = Irmin.Backend.Watch.set_listen_dir_hook Irmin_watcher.hook

let with_branch t req =
  let branch = Dream.header req "Wasmstore-Branch" in
  match branch with None -> Lwt.return t | Some branch -> with_branch t branch

let path req =
  (Dream.path req [@alert "-deprecated"]) |> Dream.drop_trailing_slash

let run ?tls ?(cors = false) ?auth ?(host = "localhost") ?(port = 6384) t =
  let () =
    Dream.log "Listening on %s:%d, tls=%b, cors=%b" host port
      (Option.is_some tls) cors
  in
  let headers = if cors then [ ("Access-Control-Allow-Origin", "*") ] else [] in
  let use_tls = Option.is_some tls in
  let key_file, certificate_file =
    match tls with
    | Some (`Key_file kf, `Cert_file cf) -> (kf, cf)
    | None -> ("", "")
  in
  let auth : (string, string) Hashtbl.t =
    match auth with
    | Some x -> Hashtbl.of_seq (List.to_seq x)
    | None -> Hashtbl.create 0
  in
  let auth f request =
    if Hashtbl.length auth = 0 then f request
    else
      let key =
        Dream.header request "Wasmstore-Auth" |> Option.value ~default:""
      in
      let perms =
        Hashtbl.find_opt auth key |> Option.map (String.split_on_char ',')
      in
      match perms with
      | Some [ "*" ] -> f request
      | Some x ->
          let exists =
            List.exists
              (fun m ->
                Dream.methods_equal (Dream.method_ request)
                  (Dream.string_to_method m))
              x
          in
          if exists then f request
          else Dream.respond ~headers ~status:`Unauthorized ""
      | None -> Dream.respond ~headers ~status:`Unauthorized ""
  in
  Dream.serve ~interface:host ~port ~key_file ~certificate_file ~tls:use_tls
  @@ Dream.logger @@ auth
  @@ Dream.router
       [
         Dream.scope "/api/v1" []
           [
             Dream.get "/modules" (fun req ->
                 let* t = with_branch t req in
                 let* modules = list t [] in
                 let modules =
                   List.map
                     (fun (k, v) ->
                       ( Irmin.Type.to_string Store.Path.t k,
                         `String (Irmin.Type.to_string Store.Hash.t v) ))
                     modules
                 in
                 Dream.json ~headers (Yojson.Safe.to_string (`Assoc modules)));
             Dream.get "/modules/**" (fun req ->
                 let* t = with_branch t req in
                 let path = path req in
                 let* modules = list t path in
                 let modules =
                   List.map
                     (fun (k, v) ->
                       ( Irmin.Type.to_string Store.Path.t k,
                         `String (Irmin.Type.to_string Store.Hash.t v) ))
                     modules
                 in
                 Dream.json ~headers (Yojson.Safe.to_string (`Assoc modules)));
             Dream.get "/module/**" (fun req ->
                 let path = path req in
                 let* t = with_branch t req in
                 let* filename = get_hash_and_filename t path in
                 match filename with
                 | Some (hash, filename) ->
                     let+ res = Dream.from_filesystem (root t) filename req in
                     let () =
                       List.iter
                         (fun (k, v) -> Dream.set_header res k v)
                         headers
                     in
                     let () =
                       Dream.set_header res "Wasmstore-Hash"
                         (Irmin.Type.to_string Store.Hash.t hash)
                     in
                     res
                 | None -> Dream.respond ~headers ~status:`Not_Found "");
             Dream.post "/module/**" (fun req ->
                 let path = path req in
                 let* t = with_branch t req in
                 let* data = Dream.body req in
                 Lwt.catch
                   (fun () ->
                     let* hash = add t path data in
                     Dream.respond ~headers
                       (Irmin.Type.to_string Store.Hash.t hash))
                   (function
                     | Wasm.Valid.Invalid (region, msg)
                     | Wasm.Decode.Code (region, msg) ->
                         let s =
                           Printf.sprintf "%s: %s"
                             (Wasm.Source.string_of_region region)
                             msg
                         in
                         Dream.respond ~headers ~status:`Bad_Request s
                     | exn -> raise exn));
             Dream.delete "/module/**" (fun req ->
                 let path = path req in
                 let* t = with_branch t req in
                 let* () = remove t path in
                 Dream.respond ~headers "");
             Dream.get "/hash/**" (fun req ->
                 let path = path req in
                 let* t = with_branch t req in
                 let* hash = hash t path in
                 match hash with
                 | Some hash ->
                     Dream.respond ~headers
                       (Irmin.Type.to_string Store.Hash.t hash)
                 | None -> Dream.respond ~headers ~status:`Not_Found "");
             Dream.post "/gc" (fun req ->
                 let* t = with_branch t req in
                 let* _ = gc t in
                 Dream.respond ~headers "");
             Dream.post "/merge/:from" (fun req ->
                 let* t = with_branch t req in
                 let from_branch = Dream.param req "from" in
                 let* res = merge t from_branch in
                 match res with
                 | Ok _ -> Dream.respond ~headers ""
                 | Error r ->
                     Dream.respond ~headers ~status:`Bad_Request
                       (Irmin.Type.to_string Irmin.Merge.conflict_t r));
             Dream.post "/restore/:commit" (fun req ->
                 let* t = with_branch t req in
                 let hash = Dream.param req "hash" in
                 let hash = Irmin.Type.of_string Store.Hash.t hash in
                 match hash with
                 | Error _ ->
                     Dream.respond ~headers ~status:`Bad_Request
                       "invalid hash in request"
                 | Ok hash -> (
                     let* commit = Store.Commit.of_hash (repo t) hash in
                     match commit with
                     | None ->
                         Dream.respond ~headers ~status:`Not_Found
                           "commit not found"
                     | Some commit ->
                         let* () = restore t commit in
                         Dream.respond ~headers ""));
             Dream.get "/snapshot" (fun req ->
                 let* t = with_branch t req in
                 let* commit = snapshot t in
                 Dream.respond ~headers
                   (Irmin.Type.to_string Store.Hash.t (Store.Commit.hash commit)));
             Dream.put "/branch/:branch" (fun req ->
                 let branch = Dream.param req "branch" in
                 let* () = Branch.switch t branch in
                 Dream.respond ~headers "");
             Dream.post "/branch/:branch" (fun req ->
                 let branch = Dream.param req "branch" in
                 let* res = Branch.create t branch in
                 match res with
                 | Ok _ -> Dream.respond ~headers ""
                 | Error (`Msg s) -> Dream.respond ~headers ~status:`Conflict s);
             Dream.delete "/branch/:branch" (fun req ->
                 let branch = Dream.param req "branch" in
                 let* () = Branch.delete t branch in
                 Dream.respond ~headers "");
             Dream.get "/branches" (fun _req ->
                 let* branches = Branch.list t in
                 Dream.respond ~headers
                   (Irmin.Type.(to_json_string (list string)) branches));
             Dream.get "/branch" (fun _req -> Dream.respond ~headers t.branch);
             Dream.get "/watch" (fun _req ->
                 Dream.websocket ~headers ~close:false (fun ws ->
                     let w = ref None in
                     let* watch =
                       watch t (fun diff ->
                           Lwt.catch
                             (fun () ->
                               let d = Yojson.Safe.to_string diff in
                               Dream.send ws d)
                             (fun _ ->
                               let* () =
                                 match !w with
                                 | Some w -> Store.unwatch w
                                 | None -> Lwt.return_unit
                               in
                               Dream.close_websocket ws))
                     in
                     w := Some watch;
                     Lwt.return_unit));
           ];
       ]
