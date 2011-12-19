staload "contrib/libevent/SATS/libevent.sats"

absviewtype longpoller (lh:addr, lb:addr)

fun longpoller_new {lh,lb:agz} (base: !event_base lb, http: !evhttp (lh, lb), url: string, poll_path: string, ping_path: string): longpoller (lh, lb)
fun longpoller_reset {lh,lb:agz} (lp: !longpoller (lb, lh)): void
fun longpoller_free {lh,lb:agz} (pf_base: !event_base lb, pf_http: !evhttp (lh, lb) | lp: longpoller (lh, lb)): void
