%% @doc Advertises `io.macula.echo' -- the hello-world target every
%% Macula SDK's own quickstart README calls first, on a fresh identity
%% that has joined nothing yet.
%%
%% ADVERTISED ON THE ALL-ZERO REALM, HARDCODED, NOT CONFIGURABLE. Every
%% SDK quickstart (macula-rust, macula-go, checked directly) calls this
%% procedure with realm `[0u8; 32]' -- the default realm a brand-new,
%% unjoined identity calls from. A realm mismatch between advertiser and
%% caller is silent (`unknown_next_peer', indistinguishable from "nobody
%% is listening"), which is the exact failure this service exists to
%% stop happening, so the realm this module advertises under is a
%% hardcoded constant rather than an environment variable: there is no
%% legitimate reason for this specific procedure to ever advertise
%% anywhere else, and a config mistake must not be able to silently
%% recreate the bug.
%%
%% NOT hecate_om's own org-namespaced capability mechanism
%% (`hecate_om_capabilities'/`hecate_echo_service:capabilities/0'):
%% that derives a procedure name as `RealmHex/Org/Name', which could
%% never produce the bare literal string every SDK's README already
%% hardcodes. This calls `macula_response:advertise/6' directly instead.
%%
%% THE PLATFORM GIVES THIS PROCEDURE NOTHING FOR FREE. `io.macula.echo'
%% is deliberately public and unauthenticated, and `macula_station_link''s
%% own inbound-call dispatch carries no rate limiting or backpressure at
%% any layer -- traced directly, not assumed. Two defenses are applied
%% here, in the handler itself, before this module existed to apply them:
%% a hard payload-size cap, and a request-rate limit (see
%% `hecate_echo_limiter'). "Let it crash" is the right default for a
%% service trusting known, cooperative callers; this is not that -- it is
%% the one procedure on the mesh a stranger is invited to call with zero
%% prior trust established.
-module(hecate_echo_mesh_rpc).

-behaviour(macula_response).

-export([start/0]).
-export([init/1, handle_request/2]).

-define(PROCEDURE, <<"io.macula.echo">>).
-define(ZERO_REALM, <<0:256>>).

%% Generous for a hello-world payload, tight for an amplification
%% attempt. Measured via `erlang:external_size/1' rather than
%% `byte_size/1' so this bounds every payload shape a caller might
%% send (map, list, number), not only a binary.
-define(MAX_PAYLOAD_EXTERNAL_SIZE, 4096).

%% @doc Advertise `io.macula.echo' on this node's mesh pool. Called once
%% from `hecate_echo_sup' at boot. Logged loudly on failure rather than
%% silently swallowed (the pattern every other hecate-* mesh RPC module
%% uses): a silent advertise failure here is precisely the "someone
%% forgot to keep the demo service running" bug this whole service
%% exists to close, just relocated one layer down.
-spec start() -> ok.
start() ->
    case hecate_om:macula_client() of
        {ok, Pool} -> do_advertise(Pool);
        {error, Reason} ->
            logger:error("[hecate_echo] no mesh pool available, "
                         "cannot advertise ~s: ~p", [?PROCEDURE, Reason])
    end.

do_advertise(Pool) ->
    case macula_response:advertise(Pool, ?ZERO_REALM, ?PROCEDURE, ?MODULE, []) of
        {ok, _Sup} ->
            logger:info("[hecate_echo] advertised ~s on the zero realm", [?PROCEDURE]);
        {error, Reason} ->
            logger:error("[hecate_echo] failed to advertise ~s: ~p", [?PROCEDURE, Reason])
    end.

%% @doc `macula_response' callback. No per-call state: rate limiting
%% lives in `hecate_echo_limiter''s own persistent table, not here --
%% `macula_response' spawns a fresh, independent process per inbound
%% call, so state threaded through THIS module's own State would reset
%% every single call and could never actually limit anything.
init([]) -> {ok, undefined}.

%% @doc `macula_response' callback: reply with the payload unchanged,
%% modulo the platform-injected `caller' key (see `strip_caller/1') and
%% the two guards below.
-spec handle_request(term(), undefined) ->
    {reply, term(), undefined} | {error, term(), undefined}.
handle_request(Payload, State) ->
    reply_for(size_verdict(Payload), Payload, State).

reply_for(too_large, _Payload, State) ->
    {error, payload_too_large, State};
reply_for(ok, Payload, State) ->
    reply_after_rate_check(hecate_echo_limiter:allow(limiter_key(Payload)), Payload, State).

reply_after_rate_check(deny, _Payload, State) ->
    {error, rate_limited, State};
reply_after_rate_check(allow, Payload, State) ->
    {reply, strip_caller(Payload), State}.

size_verdict(Payload) ->
    case erlang:external_size(Payload) of
        Size when Size > ?MAX_PAYLOAD_EXTERNAL_SIZE -> too_large;
        _Size -> ok
    end.

%% The wire-authenticated caller NodeId only reaches a handler when the
%% payload is a map (`macula_station_link:with_caller/2' merges it in
%% only then) -- every SDK quickstart's bare-text `Value::Text("hello")'
%% payload is NOT a map, so most real traffic here has no attributable
%% caller at all. Falls back to one shared global counter for that
%% traffic: a real, meaningfully weaker defense than per-caller limiting
%% for THIS traffic shape specifically, but the honest one, not a
%% per-caller limiter silently protecting nothing.
limiter_key(Payload) when is_map(Payload) ->
    maps:get(caller, Payload, '$global');
limiter_key(_Payload) ->
    '$global'.

%% `caller' is platform metadata about the call, not something the
%% caller themselves put in their own message (it deterministically
%% overwrites any same-named key they supplied -- see
%% `macula_station_link:with_caller/2''s own doc) -- an echo handler
%% that reflected it back would be showing a caller a field they never
%% actually sent.
strip_caller(Payload) when is_map(Payload) ->
    maps:remove(caller, Payload);
strip_caller(Payload) ->
    Payload.
