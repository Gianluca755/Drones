%%% utils %%%
-module(utils).
-export([sendPingLater/2]).

sendPingLater(From, To) ->
    timer:sleep(200),         % wait 200 ms
    To ! {From, ping}
.

