-module(broker).
-export([start/2]).

% private
-export([init/2, loopPrimary/2, startBck/3, loopBackup/3, sendPingLater/2]).


-record(addr, { primaryBrokerAddr = 0,
                bckBrokerAddr = 0,
                primaryManagerAddr = 0,
                bckManagerAddr = 0 }
).

% Key and value of an Order
% {ClentID, OrderID} {Source, Destination, Weight, Status}
% Status ::= awaitBck, awaitManager, inProgress, inDelivery, delivered.

% normal init
start(PrimaryManagerAddr, BckManagerAddr) ->

    Primary = spawn(broker, init, [PrimaryManagerAddr, BckManagerAddr]),
    spawn(broker, startBck, [Primary, PrimaryManagerAddr, BckManagerAddr])
.

init(PrimaryManagerAddr, BckManagerAddr) ->

    io:format("Primary broker: ~w~n", [self()]),
    % wait for bckBrokerAddr
    Temp =  receive
                {Pid, addrInit} -> Pid
            end,

    % init data structures
    AddrRecord = #addr{ bckBrokerAddr = Temp,
                        primaryManagerAddr = PrimaryManagerAddr,
                        bckManagerAddr = BckManagerAddr},

    OrderTable = ets:new(myTable, ordered_set, private),
    loopPrimary(OrderTable, AddrRecord)
.

startBck(Primary, PrimaryManagerAddr, BckManagerAddr) ->

    io:format("Backup broker: ~w~n", [self()]),
    % register bck to primaryBrokerAddr
    Primary ! {self(), addrInit},

    % init data structures
    AddrRecord = #addr{ primaryBrokerAddr = Primary,
                        primaryManagerAddr = PrimaryManagerAddr,
                        bckManagerAddr = BckManagerAddr},

    OrderTable = ets:new(myTable, ordered_set, private),

    AddrRecord#addr.primaryBrokerAddr ! ping, % send first ping
    FirstPingTime = erlang:system_time(milli_seconds),

    loopBackup(OrderTable, AddrRecord, FirstPingTime)
.


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
    % normal order
    Msg = { makeOrder, ClientID, OrderID, Source, Destination, Weight } ->
        ets:insert(OrderTable, {Source, Destination, Weight, awaitBck}),
        AddrRecord#addr.bckBrokerAddr ! Msg,
        loopPrimary(OrderTable, AddrRecord) ;

    % confirmation from bck broker
    { confirmBck, ClientID, OrderID } ->
        ets:updateTable(OrderTable, {ClientID, OrderID}, awaitManager),
        {Source, Destination, Weight, Status} = ets:lookup({ClientID, OrderID}),
        AddrRecord#addr.primaryManagerAddr ! {makeOrder, ClientID, OrderID, Source, Destination, Weight },
        loopPrimary(OrderTable, AddrRecord) ;

    % confirmation from manager
    Msg = { confirmManager, ClientID, OrderID} ->
        ets:updateTable(OrderTable, {ClientID, OrderID}, inProgress),
        AddrRecord#addr.bckBrokerAddr ! Msg,
        loopPrimary(OrderTable, AddrRecord) ;

    Msg = { droneElected, ClientID, OrderID} ->
        ets:updateTable(OrderTable, {ClientID, OrderID}, inDelivery),
        AddrRecord#addr.bckBrokerAddr ! Msg,
        loopPrimary(OrderTable, AddrRecord) ;

    % query
    { Pid, queryOrder, ClientID, OrderID } ->
        {_, _, _, Status} = ets:lookup(OrderTable, {ClentID, OrderID}),
        Pid ! Status,
        loopPrimary(OrderTable, AddrRecord) ;

    Other -> io:format("Message not expected: ~w~n", [Other])
    end
.


loopBackup(OrderTable, AddrRecord, LastPingTime) ->
    Time = erlang:system_time(milli_seconds),
    if
        Time - LastPingTime < 2000  ->
            receive
                {Sender, pingResponse} when Sender == AddrRecord#addr.primaryBrokerAddr ->
                    % if the primary responded

                    sendPingLater(self(), AddrRecord#addr.primaryBrokerAddr), % send ping after 200 ms
                    CurrentPingTime = 200 + erlang:system_time(milli_seconds),

                    loopBackup(OrderTable, AddrRecord, CurrentPingTime)

                %Other -> true
            end;

        true -> io:format("Primary broker not responding: ~w~n", [self()]) % primary not responding
    end
.


sendPingLater(From, To) ->
    timer:sleep(200),         % wait 200 ms
    To ! {From, ping}
.

%%% utils %%%

updateTable(Table, Key, NewStatus) ->
    {Source, Destination, Weight, Status} = ets:lookup(Table, Key),
    Result = ets:insert(Table, {Key, {Source, Destination, Weight, NewStatus} } ), % overwrite
    if
        Result == false ->
            io:format("Error failed attempt to modify the order table in broker. ~w~n", [{Key, {Source, Destination, Weight, NewStatus} }])
    end
.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%primaryPinger(AddrRecord) ->
%    receive
%        {AddrRecord#addr.bckPingerAddr, ping} ->
%            AddrRecord#addr.bckPingerAddr ! {self(), ok},
%            primaryPinger(AddrRecord)
%    after
%        2000 -> io:format("Backup broker not responding: ~w~n", [self()])
%    end
%.

%bckPinger(AddrRecord, LastPingTime) ->
%    receive
%        {AddrRecord#addr.primaryPinger, ok} ->
%            sleep(200), % wait 200 ms
%            AddrRecord#addr.primaryBrokerAddr ! ping,
%            CurrentPingTime = erlang:system_time(milli_seconds),
%            bckPinger(AddrRecord, CurrentPingTime)
%    after
%        2000 -> io:format("Primary broker not responding: ~w~n", [self()]),
%                AddrRecord#adrr.bckBrokerAddr ! {self(), primaryDown}
%    end
%.
