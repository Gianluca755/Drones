-module(broker).
-export([start/2]).

% private
-export([startPrimary/2, loopPrimary/2, startBck/3, loopBackup/3]).

-record(addr, { primaryBrokerAddr = 0,
                bckBrokerAddr = 0,
                primaryManagerAddr = 0,
                bckManagerAddr = 0 }
).

% Key and value of an Order
% {ClientID, OrderID} {Source, Destination, Weight, Status}
% Status ::= savedNotSent,      saved,      inProgress,    inDelivery,    delivered.
% bck Status ::= savedNotSent,       saved,         inProgress,    inDelivery,    delivered.

% normal init
start(PrimaryManagerAddr, BckManagerAddr) ->

    Primary = spawn(broker, startPrimary, [PrimaryManagerAddr, BckManagerAddr]),
    spawn(broker, startBck, [Primary, PrimaryManagerAddr, BckManagerAddr])
.

startPrimary(PrimaryManagerAddr, BckManagerAddr) ->

    io:format("Primary broker: ~w~n", [self()]),
    % wait for bckBrokerAddr
    Temp =  receive
                {Pid, addrInit} -> Pid
            end,

    % init data structures
    AddrRecord = #addr{ primaryBrokerAddr = self(),
                        bckBrokerAddr = Temp,
                        primaryManagerAddr = PrimaryManagerAddr,
                        bckManagerAddr = BckManagerAddr},

    OrderTable = ets:new(myTable, ordered_set, public),
    loopPrimary(OrderTable, AddrRecord)
.

startBck(Primary, PrimaryManagerAddr, BckManagerAddr) ->

    io:format("Backup broker: ~w~n", [self()]),
    % register bck to primaryBrokerAddr
    Primary ! {self(), addrInit},

    % init data structures
    AddrRecord = #addr{ primaryBrokerAddr = Primary,
                        bckBrokerAddr = self(),
                        primaryManagerAddr = PrimaryManagerAddr,
                        bckManagerAddr = BckManagerAddr},

    OrderTable = ets:new(myTable, ordered_set, public),

    AddrRecord#addr.primaryBrokerAddr ! ping, % send first ping
    FirstPingTime = erlang:system_time(milli_seconds),

    loopBackup(OrderTable, AddrRecord, FirstPingTime)
.

%%% end init %%%

%%% processes loops %%%

loopPrimary(OrderTable, AddrRecord) ->
    % the ping msg has higher priority
    % the primary server respong immediately, while the backup has some delay to mantain 5 pckt/second
    receive
        {Sender, ping} when Sender == AddrRecord#addr.bckBrokerAddr ->
            AddrRecord#addr.bckBrokerAddr ! {self(), pingResponse}
    after
        0 -> true
    end,

    receive
    % query of an order
    { Pid, queryOrder, ClientID, OrderID } ->
        respondQuery(Pid, OrderTable, ClientID, OrderID) ;

    % Client sends an order
    { makeOrder, _, _, _, _, _ } = Msg ->
        Handler = spawn( broker, handleOrderPrimary, [OrderTable, AddrRecord] ),
        AddrRecord#addr.bckBrokerAddr ! {makeOrder, Handler},
        Handler ! Msg % let the new handler process the order


    % Timeout is for the case where the server has no incoming messages for a long period of time, it still has to respond to the ping
    % but the 10 is for preventing aggressive looping of the process
    after
        10 -> true
    end,

    loopPrimary(OrderTable, AddrRecord)
.


loopBackup(OrderTable, AddrRecord, LastPingTime) ->
    Time = erlang:system_time(milli_seconds),
    if
        Time - LastPingTime < 2000  ->
            receive
                %% ping msg case
                {Sender, pingResponse} when Sender == AddrRecord#addr.primaryBrokerAddr ->
                    % if the primary responded

                    sendPingLater(self(), AddrRecord#addr.primaryBrokerAddr), % send ping after 200 ms
                    CurrentPingTime = 200 + erlang:system_time(milli_seconds),

                    loopBackup(OrderTable, AddrRecord, CurrentPingTime)

                %% other cases
            end;

        true -> io:format("Primary broker not responding: ~w~n", [self()]) % primary not responding
    end
.




%%% utils %%%

sendPingLater(From, To) ->
    timer:sleep(200),         % wait 200 ms
    To ! {From, ping}
.

respondQuery(Pid, OrderTable, ClientID, OrderID) ->
    {_, _, _, Status} = ets:lookup(OrderTable, {ClientID, OrderID}),
    Pid ! Status
.

updateTableStatus(Table, Key, NewStatus) ->
    {Source, Destination, Weight, _Status} = ets:lookup(Table, Key),
    Result = ets:insert(Table, {Key, {Source, Destination, Weight, NewStatus} } ), % overwrite
    if
        Result == false ->
            io:format("Error failed attempt to modify the order table in broker. ~w~n", [{Key, {Source, Destination, Weight, NewStatus} }])
    end
.

