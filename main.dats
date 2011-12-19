staload "libc/SATS/signal.sats"
staload "prelude/SATS/unsafe.sats"
staload "contrib/libevent/SATS/libevent.sats"
staload "longpoll.sats"

dynload "longpoll.dats"

fun sigint_callback (fd: evutil_socket_t, what: sint, base: !event_base1):void = {
  val () = printf("Cleaning up...\n", @())
  val r = event_base_loopexit(base, null)
  val () = assertloc (r = 0)
}

implement main (argc, argv) = {
  val () = assertloc (argc = 5)

  val url = argv.[1]
  val port = int1_of (argv.[2])

  val () = printf("Starting longpoller for server %s on port %d, poll path is %s and ping path is %s\n", @(url, port, argv.[3], argv.[4]))

  val _ = signal (SIGPIPE, SIG_IGN)

  val base = event_base_new ()
  val () = assertloc (~base)

  val http = evhttp_new(base)
  val () = assertloc (~http)

  val lp = longpoller_new (base, http, url, argv.[3], argv.[4])

  val b = __ref (base) where { extern castfn __ref {l:agz} (b: !event_base l): event_base l }
  val sigint = event_new_noref {event_base1} (base, cast {evutil_socket_t} (SIGINT), cast {sint} (EV_SIGNAL lor EV_PERSIST), sigint_callback, b)
  val () = assertloc (~sigint)
  val _ = __unref (b) where { extern castfn __unref {l:agz} (b: event_base l): ptr l }

  val r = event_add_null (sigint, null)
  val () = assertloc (r = 0)

  val r = evhttp_bind_socket(http, "0.0.0.0", uint16_of_int(port))
  val () = assertloc (r = 0)
 
  val r = event_base_dispatch(base)
  val () = assertloc (r = 0)

  val () = event_free (sigint)

  val () = longpoller_free (base, http | lp)

  val () = evhttp_free(base | http)
  val () = event_base_free(base)
}

