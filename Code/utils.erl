%%% utils %%%

sendPingLater(From, To) ->
    timer:sleep(200),         % wait 200 ms
    To ! {From, ping}
.

updateTableStatus(Table, Key, NewStatus) ->
    {Source, Destination, Weight, _Status} = ets:lookup(Table, Key),
    Result = ets:insert(Table, {Key, {Source, Destination, Weight, NewStatus} } ), % overwrite
    if
        Result == false ->
            io:format("Error failed attempt to modify the order table in broker. ~w~n", [{Key, {Source, Destination, Weight, NewStatus} }])
    end
.
