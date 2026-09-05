%% @doc Supervises this service's own processes.
%%
%% Two children: the rate-limiter table owner (must be up before any call
%% can be answered, so it starts first) and the advertiser (calls
%% `macula_response:advertise/6' once at boot; a crash-restart here
%% re-advertises, which is the correct response to losing the process
%% that made the advertisement in the first place).
-module(hecate_echo_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Children = [
        #{id => hecate_echo_limiter,
          start => {hecate_echo_limiter, start_link, []},
          restart => permanent,
          shutdown => 5000,
          type => worker},
        #{id => hecate_echo_advertiser,
          start => {hecate_echo_advertiser, start_link, []},
          restart => permanent,
          shutdown => 5000,
          type => worker}
    ],
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10}, Children}}.
