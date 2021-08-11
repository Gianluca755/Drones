-module(manager).

-export([start/0]).
-export([startPrimary/2, loopPrimary/2, startBck/3, loopBackup/3]).

-record(addr, { primaryBrokerAddr = 0,
                bckBrokerAddr = 0,
                primaryManagerAddr = 0,
                bckManagerAddr = 0 }
).


start() ->

    Primary = spawn(manager, startPrimary, []),
    Bck = spawn(manager, startBck, [Primary]),

    io:format("Primary manager: ~w~n", [Primary]),
    io:format("Backup manager: ~w~n", [Bck])
.

startPrimary(PrimaryBrokerAddr, BckBrokerAddr) ->

    % wait for bckBrokerAddr
    Temp =  receive
                {Pid, addrInit} -> Pid
            end,

    % init data structures
    AddrRecord = #addr{ primaryBrokerAddr = PrimaryBrokerAddr,
                        bckBrokerAddr = BckBrokerAddr,
                        primaryManagerAddr = self(),
                        bckManagerAddr = Temp},

    OrderTable = ets:new(myTable, ordered_set, public),
    loopPrimary(OrderTable, AddrRecord)
.

startBck(Primary, PrimaryBrokerAddr, BckBrokerAddr) ->

    % register bck to primaryBrokerAddr
    Primary ! {self(), addrInit},

    % init data structures
    AddrRecord = #addr{ primaryBrokerAddr = PrimaryBrokerAddr,
                        bckBrokerAddr = BckBrokerAddr,
                        primaryManagerAddr = Primary,
                        bckManagerAddr = self()},

    OrderTable = ets:new(myTable, ordered_set, public),

    AddrRecord#addr.primaryManagerAddr ! ping, % send first ping
    FirstPingTime = erlang:system_time(milli_seconds),

    loopBackup(OrderTable, AddrRecord, FirstPingTime)
.

%%% end init %%%


%%% processes loops %%%

loopPrimary(OrderTable, AddrRecord) ->
    % the ping msg has higher priority
    % the primary server respong immediately, while the backup has some delay to mantain 5 pckt/second
    receive
        {Sender, ping} when Sender == AddrRecord#addr.bckManagerAddr ->
            AddrRecord#addr.bckManagerAddr ! {self(), pingResponse}
    after
        0 -> true
    end,

    receive

    % receive make order, save, reply to broker with inProgress, select drone
    { makeOrder, _, _, _, _, _ } = Msg ->
        Handler = spawn( broker, handleOrderPrimary, [OrderTable, AddrRecord] ),
        Handler ! Msg   % let the new handler apply the order

    % receive inDelivery from a drone, save info and new status, inform the broker

    % receive delivered from a drone, save info and new status, inform the broker

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
                {Sender, pingResponse} when Sender == AddrRecord#addr.primaryManagerAddr ->
                    % if the primary responded

                    utils:sendPingLater(self(), AddrRecord#addr.primaryManagerAddr), % send ping after 200 ms
                    CurrentPingTime = 200 + erlang:system_time(milli_seconds),

                    loopBackup(OrderTable, AddrRecord, CurrentPingTime);

                %% other cases
                {newHandler, Pid} -> spawn(broker, handleOrderBck, [OrderTable, AddrRecord, Pid])

            end;

        true -> io:format("Primary manager not responding: ~w~n", [self()]) % primary not responding
    end
.


%%% handlers %%%

handleOrderPrimary(OrderTable, AddrRecord) ->
    AddrRecord#addr.bckManagerAddr ! {newHandler, self()},
    % wait for handler of the backup
    receive {bindAdderess, PidBckHandler} -> true
    end
.


handleOrderBck(OrderTable, AddrRecord, PrimaryHandlerAddr) ->
    PrimaryHandlerAddr ! {bindAdderess, self()},

.












