%% @doc The hecate_om service contract: what this service is and may do.
%%
%% SIX CALLBACKS, ALL REQUIRED. hecate_om resolves them BY NAME at startup, on a
%% live node, so a service that forgets one dies with `undef' where nobody is
%% watching. The `-behaviour' attribute below is what turns that into a compile
%% error instead, and the generated test suite guards the attribute itself.
-module(hecate_echo_service).

-behaviour(hecate_om_service).

-export([info/0, start/1, stop/1, health/0, capabilities/0, identity_spec/0]).

%% Every SDK quickstart calls `io.macula.echo' from a fresh identity that has
%% joined nothing yet -- the all-zero realm. See `capabilities/0'.
-define(EXPECTED_REALM, <<0:256>>).

info() ->
    #{name => <<"hecate-echo">>,
      version => <<"0.1.0">>,
      description => <<"Always-on io.macula.echo, the mesh's hello-world target every SDK quickstart calls">>}.

start(_Opts) -> hecate_echo_sup:start_link().

stop(_State) -> ok.

%% Green once the supervision tree is up. Replace this with a real probe of
%% whatever this service needs in order to do its job. A dark mesh is usually NOT
%% a health failure: decide that deliberately rather than by default.
health() -> ok.

%% `io.macula.echo' is advertised through the standard `hecate_om_capabilities'
%% path like any other capability -- `advertise_one/7' already registers each
%% capability under both its bare `Name' and the org-qualified
%% `Org/Name', so the bare literal string every SDK quickstart hardcodes needs
%% no bypass, and this service gets that mechanism's periodic re-advertise and
%% TTL for free instead of a one-shot, boot-time-only call.
%%
%% `hecate_om_capabilities' resolves ONE realm for the whole batch, from this
%% node's own live identity. A realm mismatch between advertiser and caller is
%% silent on the wire (`unknown_next_peer', indistinguishable from "nobody is
%% listening"), which is the exact failure this service exists to stop
%% happening -- so the realm is asserted here, crash-loud, rather than trusted
%% to a config value nothing would notice going wrong. `capabilities/0' runs as
%% an argument to `hecate_om_capabilities:register/1' inside `hecate_om:boot/2',
%% by which point `hecate_om_identity' is already up (OTP application-start
%% ordering starts it ahead of the service module's own boot), so there is no
%% race to guard against here, only a config value to check.
capabilities() ->
    ok = assert_expected_realm(),
    [#{name => <<"io.macula.echo">>,
       version => 1,
       handler => {hecate_echo_mesh_rpc, []},
       auth => open}].

assert_expected_realm() ->
    checked_realm(hecate_om_identity:realm()).

checked_realm({ok, ?EXPECTED_REALM}) -> ok;
checked_realm(Other) -> error({hecate_echo_realm_mismatch, Other}).

%% THE AUTHORITY THIS SERVICE ASKS THE REALM FOR, and deliberately nothing more.
%% Ask for exactly the topics you publish and subscribe to. Popped, an attacker
%% gains precisely this and no more, which is the whole point of listing it.
%%
%% The scope is claimed now because it is the namespace every later resource
%% hangs under, and a scope costs nothing while a rename costs every deployed
%% peer.
identity_spec() ->
    #{scope => <<"hecate-echo">>,
      actions => [],
      resources => [],
      ttl_days => 30}.
