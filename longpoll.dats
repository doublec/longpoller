staload "contrib/libevent/SATS/libevent.sats"
staload "libc/sys/SATS/time.sats"
staload "prelude/SATS/list_vt.sats"
staload "prelude/DATS/list_vt.dats"
staload "prelude/DATS/pointer.dats"

staload "prelude/SATS/unsafe.sats"
staload "longpoll.sats"

viewtypedef request_data (l_req:addr) = @{ req= evhttp_request l_req, auth= strptr1 }
viewtypedef request_data = [l1:agz] request_data (l1)

(*
  requests= the list of clients waiting for a response from the server
  responses= the list of clients we are in the process of replying to 

  When a block is found the current list of 'requests' is added to 'responses' and they are processed
  in order, responding with the block data.
*)
viewtypedef context = @{ host= strptr1, port= uint16, path= strptr1, requests= List_vt (request_data), responses= List_vt (request_data), timer= Option_vt event1 }

fn evbuffer_of_string (s: string): [l:agz] evbuffer l = let
  val buffer = evbuffer_new ()
  val () = assertloc (~buffer)

  val s = string1_of_string (s)
  val r = evbuffer_add_string (buffer, s, string1_length (s))
  val () = assertloc (r = 0)
in
  buffer
end

fn context_new (host: strptr1, port: uint16, path: strptr1): [l:agz] (free_gc_v (context?, l), context @ l | ptr l) = let
  val (pf_gc, pf_at | p) = ptr_alloc<context> ()
  val () = p->host := host
  val () = p->port := port
  val () = p->path := path
  val () = p->requests := list_vt_nil
  val () = p->responses := list_vt_nil
  val () = p->timer := None_vt
in
  (pf_gc, pf_at | p)
end

fn context_start_timer {l:agz} (base: !event_base l, ctx: &context, seconds: int): void = {
  fun timer_callback (fd: evutil_socket_t, what: sint, ctx: &context):void = {
    fun ping_request (data: &request_data): void = {
      val (pff_conn | conn) = evhttp_request_get_connection (data.req)
      val () = if ~conn then {
                 val buffer = evbuffer_of_string (" ")
                 val () = evhttp_send_reply_chunk (data.req, buffer)
                 val () = evbuffer_free (buffer)
               }
               else ()
      prval () = pff_conn (conn)
    }
    val () = list_vt_foreach_fun (ctx.requests, ping_request)
  }

  val () = assertloc (seconds > 0)

  val timer = event_new {context} (base, cast {evutil_socket_t} (~1), cast {sint} (EV_PERSIST), timer_callback, ctx)
  val () = assertloc (~timer)

  var timeout: timeval
  val () = timeout.tv_sec := cast {time_t} (seconds)
  val () = timeout.tv_usec := cast {suseconds_t} (0) 
  val r = event_add (timer, timeout)
  val () = assertloc (r = 0)

  val () = case+ ctx.timer of
           | ~Some_vt t => {
                             val () = event_free (t)
                             val () = ctx.timer := Some_vt timer
                           }
           | ~None_vt () => (ctx.timer := Some_vt timer)
}

fun free_request_data (requests: List_vt (request_data)) = 
  case+ requests of 
    | ~list_vt_nil () => ()
    | ~list_vt_cons (data, xs) => {
                                    val () = strptr_free (data.auth)
                                    val () = evhttp_send_reply_end (data.req)
                                    val () = free_request_data (xs)
                                  }

fn context_free {l:agz} (pf_gc: free_gc_v (context?, l), pf_at: context @ l | p: ptr l): void = let 
  val () = strptr_free (p->host)
  val () = strptr_free (p->path)
  val () = free_request_data (p->requests)
  val () = free_request_data (p->responses)
  val () = case+ p->timer of
           | ~Some_vt t => event_free (t)
           | ~None_vt () => ()
in
  ptr_free {context?} (pf_gc, pf_at | p)
end


fun send_html (req: evhttp_request1, code: int, reason: string, html: string): void = {
  val buffer = evbuffer_of_string (html)
  val () = evhttp_send_reply (req, 200, "OK", buffer)
  val () = evbuffer_free (buffer)
}

viewtypedef getwork_callback = (!evhttp_request1) -<lincloptr1> void
dataviewtype getwork_data (lc:addr) = getwork_data_container (lc) of (evhttp_connection lc, getwork_callback)

fun handle_getwork {l:agz} (client: !evhttp_request1, c: getwork_data l):void = let
  val ~getwork_data_container (cn, cb) = c
  val () = cb (client)
  val () = cloptr_free (cb)
in
  evhttp_connection_free (cn)
end

typedef evhttp_callback (t1:viewt@ype) = (!evhttp_request1, t1) -> void
extern fun evhttp_make_request(cn: evhttp_connection1, req: evhttp_request1, type: evhttp_cmd_type, uri: string):[n:int | n == ~1 || n == 0] int n = "mac#evhttp_make_request"
extern fun evhttp_request_new {a:viewt@ype} (callback: evhttp_callback (a), arg: a): evhttp_request0 = "mac#evhttp_request_new"

fun send_getwork {l:agz} (base: !event_base l, host: string, port: uint16, path: string, auth: string, cb: getwork_callback): void = {
  val [lc:addr] cn = evhttp_connection_base_new(base,
                                                null,
                                                host,
                                                port)
  val () = assertloc (~cn)

  val c = __ref (cn) where { extern castfn __ref {l:agz} (b: !evhttp_connection l): evhttp_connection l }
  val container = getwork_data_container (c, cb)

  val client = evhttp_request_new {getwork_data lc} (handle_getwork, container) 
  val () = assertloc (~client)

  val (pff_headers | headers) = evhttp_request_get_output_headers(client)
  val r = evhttp_add_header(headers, "Host", host)
  val () = assertloc (r = 0)

  val r = evhttp_add_header(headers, "Authorization", auth)
  val () = assertloc (r = 0)

  val r = evhttp_add_header(headers, "Content-Type", "application/json")
  val () = assertloc (r = 0)

  val () = printf("Host: %s Port %d Auth %s\n", @(host, int_of_uint16 port, auth))

  val (pff_buffer | buffer) = evhttp_request_get_output_buffer (client)
  val s = "{\"method\":\"getwork\",\"params\":[],\"id\":\"0\"}";
  val r = evbuffer_add_string (buffer, s, string1_length (s))
  val () = assertloc (r = 0)
  prval () = pff_buffer (buffer)

  val r = evhttp_make_request(cn, client, EVHTTP_REQ_POST, path)
  val () = assertloc (r = 0)

  prval () = pff_headers (headers)
}

fun handle_response(ctx: &context): void =
    case+ ctx.responses of
      | ~list_vt_nil () => ctx.responses := list_vt_nil
      | ~list_vt_cons (data, xs) => {
                                      val req = data.req
                                      val auth = data.auth
                                      val () = ctx.responses := xs
                                      val (pff_conn | conn) = evhttp_request_get_connection (req)
                                      val (pff_base | base) = evhttp_connection_get_base (conn)
                                      val () = if ~conn then {
                                        prval pf_ctx = __ref (view@ ctx) where { extern prfun __ref {l:agz} (r: !context @ l): context @ l }  

                                        val cb: getwork_callback = llam (client: !evhttp_request1): void =<lincloptr1> let
                                          val () = handle_response (ctx)
                                          prval () = consume_ctx (pf_ctx) where { extern prval consume_ctx {l:agz} (pf: context @ l): void }
                                          val code = if evhttp_request_isnot_null (client) then evhttp_request_get_response_code(client) else 501
                                        in
                                          if code = HTTP_OK then {
                                            val (pff_in | inbuf) = evhttp_request_get_input_buffer (client)
                                            val outbuf = evbuffer_new ()
                                            val () = assertloc (~outbuf)

                                            val r = evbuffer_add_buffer (outbuf, inbuf)
                                            val () = assertloc (r = 0)

                                            val () = evhttp_send_reply_chunk (req, outbuf)
                                            val () = evhttp_send_reply_end (req)
                                            prval () = pff_in (inbuf)
                                            val () = evbuffer_free (outbuf)
                                          }
                                          else {
                                            val () = printf("result: %d\n", @(code))
                                            val buffer = evbuffer_of_string ("{\"result\":null,\"error\":{\"code\":-1,\"message\":\"Could not contact daemon\"},\"id\":1}")
                                            val () = evhttp_send_reply_chunk (req, buffer)
                                            val () = evhttp_send_reply_end (req)
                                            val () = evbuffer_free (buffer)
                                         }
                                        end

                                        val () = send_getwork (base, castvwtp1 {string} (ctx.host), ctx.port, castvwtp1 {string} (ctx.path), castvwtp1 {string} (auth), cb)
                                      }
                                      else {
                                        val () = evhttp_send_reply_end (req)
                                        val () = handle_response (ctx)
                                      }
                                      val () = strptr_free (auth)
                                      prval () = pff_base (base)
                                      prval () = pff_conn (conn)
                                    }

fun newblock_callback (req: evhttp_request1, ctx: &context): void = {
  val () = ctx.responses := list_vt_append (ctx.responses, ctx.requests)
  val () = ctx.requests := list_vt_nil 
  val () = handle_response(ctx)
  val () = send_html (req, 200, "OK", "<html><body>Ping handled</body></html>")
}

fun longpoll_callback (req: evhttp_request1, ctx: &context): void = {
  val (pff_headers | headers) = evhttp_request_get_input_headers (req)
  val (pff_auth | auth) = evhttp_find_header (headers, "Authorization")
  val () = if strptr_is_null (auth) then 
             evhttp_send_error (req, 401, "Unauthorized")
           else {
             val () = assertloc (strptr_isnot_null (auth))
             val () = evhttp_send_reply_start (req, 200, "OK")

             val auth = strptr_dup (auth) 
             val () = ctx.requests := list_vt_cons (@{ req= req, auth= auth}, ctx.requests)
             val () = printf("Request count: %d\n", @(list_vt_length (ctx.requests)))
             
           }
  prval () = pff_auth (auth)
  prval () = pff_headers (headers)
}


typedef evhttp_callback (t1:viewt@ype) = (evhttp_request1, &t1) -> void
extern fun evhttp_set_cb {a:viewt@ype} {lh,lb:agz} (http: !evhttp (lh, lb), path: string, callback: evhttp_callback (a), arg: &a): [n:int | n == ~2 || n == ~1 || n == 0] int n = "mac#evhttp_set_cb"

assume longpoller (lh:addr, lb:addr) = [l:agz] @{ gcview= free_gc_v (context?, l), atview= context @ l, ptr= ptr l }

implement longpoller_new {lh,lb} (base, http, url, poll_path, ping_path) = let
  val uri = evhttp_uri_parse (url)
  val () = assertloc (~uri)

  val (pff_host | host) = evhttp_uri_get_host (uri)
  val () = assertloc (strptr_isnot_null (host))

  val port = evhttp_uri_get_port (uri)
  val () = assertloc (port >= 80)
  val port = uint16_of_int port

  val (pff_path | path) = evhttp_uri_get_path (uri)
  val () = assertloc (strptr_isnot_null (path))

  val (pf_gc, pf_ctx | ctx) = context_new (strptr_dup (host), port, strptr_dup (path))
  prval () = pff_path (path)
  prval () = pff_host (host)
  val () = evhttp_uri_free (uri)

  val () = context_start_timer (base, !ctx, 60)

  val r = evhttp_set_cb {context} (http, poll_path, longpoll_callback, !ctx) 
  val () = assertloc (r = 0)

  val r = evhttp_set_cb {context} (http, ping_path, newblock_callback, !ctx)
  val () = assertloc (r = 0)
in
  @{ gcview= pf_gc, atview= pf_ctx, ptr= ctx }
end

implement longpoller_reset {lh,lb} (lp) = {
  prval pf = lp.atview
  val p = lp.ptr
  val () = free_request_data (p->requests)
  val () = p->requests := list_vt_nil
  prval () = lp.atview := pf
}

implement longpoller_free {lh,lb} (pf_base, pf_http | lp) = {
  val () = context_free (lp.gcview, lp.atview | lp.ptr)
}


