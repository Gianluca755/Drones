-module(broker).
-export([start/2]).

% private
-export([startPrimary/2, loopPrimary/2, startBck/3, loopBackup/3]).
-export([handleOrderPrimary/2, handleOrderBck/3, sendPingLater/2, respondQuery/4]).


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
                {Sender, pingResponse} when Sender == AddrRecord#addr.primaryBrokerAddr ->
                    % if the primary responded

                    sendPingLater(self(), AddrRecord#addr.primaryBrokerAddr), % send ping after 200 ms
                    CurrentPingTime = 200 + erlang:system_time(milli_seconds),

                    loopBackup(OrderTable, AddrRecord, CurrentPingTime)
            end;

        true -> io:format("Primary broker not responding: ~w~n", [self()]) % primary not responding
    end
.


handleOrderPrimary(OrderTable, AddrRecord) ->
    receive {bindAdderess, PidBckHandler} -> PidBckHandler ! {bindAdderess, self()} % wait for handler of the backup
    end,
    %1
    receive Msg = { makeOrder, ClientID, OrderID, Source, Destination, Weight } ->
        ets:insert(OrderTable, { {ClientID, OrderID}, {Source, Destination, Weight, savedNotSent} }),
        PidBckHandler ! Msg
    end,
    %3
    receive confirmBck ->   updateTableStatus(OrderTable, {ClientID, OrderID}, saved),
                            PidBckHandler ! confirmPrimary,
                            % !!! need to send confirmation to client

                            AddrRecord#addr.primaryManagerAddr ! { makeOrder, self(), ClientID, OrderID, Source, Destination, Weight }
    end,

    % wait for the response of an handler of the manager
    receive {bindAdderess, PidManager} -> true
    end,

    %5
    receive confirmManager -> PidBckHandler ! confirmManager
    end,

    %7
    receive confirmBck -> updateTableStatus(OrderTable, {ClientID, OrderID}, inProgress),
                          PidBckHandler ! confirmPrimary
    end,

    %9
    receive confirmExecution -> PidBckHandler ! confirmExecution
    end,
    %11
    receive confirmBck ->   updateTableStatus(OrderTable, {ClientID, OrderID}, inDelivery),
                            PidBckHandler ! confirmPrimary
    end,
    %13
    receive confirmDelivered -> PidBckHandler ! confirmDelivered
    end,
    %15
    receive confirmBck ->   updateTableStatus(OrderTable, {ClientID, OrderID}, delivered),
                            PidBckHandler ! confirmPrimary
    end
.

handleOrderBck(OrderTable, AddrRecord, PidPrimaryHandler) ->
    PidPrimaryHandler ! {bindAdderess, self()}, % send address to primary handler
    %2
    receive { makeOrder, ClientID, OrderID, Source, Destination, Weight } ->
        ets:insert(OrderTable, { {ClientID, OrderID}, {Source, Destination, Weight, savedNotSent}} ),
        PidPrimaryHandler ! confirmBck
    end,
    %4
    receive confirmPrimary -> updateTableStatus(OrderTable, {ClientID, OrderID}, saved)
    end,
    %6
    receive confirmManager -> PidPrimaryHandler ! confirmBck
    end,
    %8
    receive confirmPrimary -> updateTableStatus(OrderTable, {ClientID, OrderID}, inProgress)
    end,
    %10
    receive confirmExecution -> PidPrimaryHandler ! confirmBck
    end,
    %12
    receive confirmPrimary -> updateTableStatus(OrderTable, {ClientID, OrderID}, inDelivery)
    end,
    %14
    receive confirmDelivered -> PidPrimaryHandler ! confirmBck
    end,
    %16
    receive confirmPrimary -> updateTableStatus(OrderTable, {ClientID, OrderID}, delivered)
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

