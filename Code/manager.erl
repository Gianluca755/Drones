-module(manager).

-export([start/0]).



start() ->

    Primary = spawn(manager, startPrimary, []),
    Bck = spawn(manager, startBck, [Primary]),

    io:format("Primary manager: ~w~n", [Primary]),
    io:format("Backup manager: ~w~n", [Bck])
.





























