-module(broker).
-export([start/2]).

% private
-export([startPrimary/2, loopPrimary/2, startBck/3, loopBackup/3]).
-export([handlerOrderPrimary/2, handlerOrderBck/3]).

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
    Bck = spawn(broker, startBck, [Primary, PrimaryManagerAddr, BckManagerAddr]),
    io:format("Primary broker: ~w~n", [Primary]),
    io:format("Backup broker: ~w~n", [Bck])
.

startPrimary(PrimaryManagerAddr, BckManagerAddr) ->

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

    % Handles all the cases of execution of the order
    { Type, _, _, _, _, _ } = Msg when Type == makeOrder ; Type == inProgress ; Type == inDelivery ; Type == delivered ->
        Handler = spawn( broker, handlerOrderPrimary, [OrderTable, AddrRecord] ),
        Handler ! Msg   % let the new handler apply the order


    % Timeout is for the case where the server has no incoming messages for a long period of time,
    % it still has to respond to the ping but the 10 is for preventing aggressive looping of the process
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

                    utils:sendPingLater(self(), AddrRecord#addr.primaryBrokerAddr), % send ping after 200 ms
                    CurrentPingTime = 200 + erlang:system_time(milli_seconds),

                    loopBackup(OrderTable, AddrRecord, CurrentPingTime);

                %% other cases
                {newHandler, Pid} -> spawn(broker, handlerOrderBck, [OrderTable, AddrRecord, Pid])

            end;

        true -> io:format("Primary broker not responding: ~w~n", [self()]) % primary not responding
    end
.

%%% handlers %%%

handlerOrderPrimary(OrderTable, AddrRecord) ->

    AddrRecord#addr.bckBrokerAddr ! {newHandler, self()},
    % wait for handler of the backup
    receive {bindAdderess, PidBckHandler} -> true
    end,
    % process the msg and bind the variables
    receive { Type, PidSource, ClientID, OrderID, Description } = Msg
            when Type == makeOrder ; Type == inProgress ; Type == inDelivery ; Type == delivered -> true
    end,

    PidBckHandler ! Msg, % send msg to broker bck
    receive confirmBck -> true
    end,
    % saving the status order
    if
        Type == makeOrder ->
            {Source, Destination, Weight} = Description, % extract values
            ets:insert(OrderTable, { {ClientID, OrderID}, {Source, Destination, Weight, saved} } ),
            PidSource ! confirmOrder , % send ack to the client
            AddrRecord#addr.primaryManagerAddr ! Msg  % send order to the manager
            ;
        true -> utils:updateTableStatus(OrderTable, {ClientID, OrderID}, Type) % Type is the new state
    end
.

handlerOrderBck(OrderTable, AddrRecord, PrimaryHandlerAddr) ->
    PrimaryHandlerAddr ! {bindAdderess, self()},

    receive { Type, _PidSource, ClientID, OrderID, Description }
            when Type == makeOrder ; Type == inProgress ; Type == inDelivery ; Type == delivered -> true
    end,
    if
        Type == makeOrder ->
            {Source, Destination, Weight} = Description, % extract values
            ets:insert(OrderTable, { {ClientID, OrderID}, {Source, Destination, Weight, saved} } );
        true -> utils:updateTableStatus(OrderTable, {ClientID, OrderID}, Type) % Type is the new state
    end,

    PrimaryHandlerAddr ! confirmBck
.


respondQuery(Pid, OrderTable, ClientID, OrderID) ->
    {_, _, _, Status} = ets:lookup(OrderTable, {ClientID, OrderID}),
    Pid ! Status
.

