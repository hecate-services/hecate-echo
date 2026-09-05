%% @doc Triggers the one-shot `io.macula.echo' mesh advertisement at
%% boot, and stays alive as a supervised child so a crash here restarts
%% (and re-advertises) rather than leaving the procedure silently
%% unreachable for the rest of this node's uptime.
%%
%% A trivial wrapper is worth its own module: `hecate_echo_mesh_rpc'
%% implements the `macula_response' behaviour (per-call request
%% handling), a genuinely different responsibility from "call advertise
%% once when this node boots" -- conflating them would make it unclear
%% which module a `-behaviour(macula_response)' attribute actually
%% governs.
-module(hecate_echo_advertiser).

-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    hecate_echo_mesh_rpc:start(),
    {ok, undefined}.

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.
