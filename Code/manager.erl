-module(manager).

-export([start/0]).


-export([startPrimary/2, loopPrimary/3, startBck/3, loopBackup/4]).
-export([handlerOrderPrimary/3, handlerOrderBck/4]).
-export([pick_rand/1, pick_rand/2, pick_rand/3 ]).


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
    DroneTable = ets:new(droneTable, ordered_set, public),
    loopPrimary(OrderTable, AddrRecord, DroneTable)
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
    DroneTable = ets:new(droneTable, ordered_set, public),

    AddrRecord#addr.primaryManagerAddr ! ping, % send first ping
    FirstPingTime = erlang:system_time(milli_seconds),

    loopBackup(OrderTable, AddrRecord, DroneTable, FirstPingTime)
.

%%% end init %%%


%%% processes loops %%%

loopPrimary(OrderTable, AddrRecord, DroneTable) ->
    % the ping msg has higher priority
    % the primary server respong immediately, while the backup has some delay to mantain 5 pckt/second
    receive
        {Sender, ping} when Sender == AddrRecord#addr.bckManagerAddr ->
            AddrRecord#addr.bckManagerAddr ! {self(), pingResponse}
    after
       0 -> true
    end,

    receive
	
	{joinRequest, Drone_Address, DroneID, {}, weight}->	
		Size = ets:info(DroneTable, size),
		case Size of
			0 -> DronesList= spawn(manager, create_drone_list, [DroneTable, [], 0, Drone_Address]);
			1 -> DronesList= spawn(manager, create_drone_list, [DroneTable, [], 1, Drone_Address]);
			2 -> DronesList= spawn(manager, create_drone_list, [DroneTable, [], 2, Drone_Address]);
			true -> DronesList= spawn(manager, create_drone_list, [DroneTable, [], 3, Drone_Address])
		end,
		ets:insert (DroneTable, {Drone_Address, DroneID});
		
		
		
	
    % receive make order, save, reply to broker with inProgress, select random drone
    % receive inDelivery (means elected) from a drone, save info and new status, inform the broker
    % receive delivered from a drone, save info and new status, inform the broker
    { Type, _Client_or_Drone_Address, _ClientID, _OrderID, _Description } = Msg
    when Type == makeOrder ; Type == inDelivery ; Type == inProgress ->
        Handler = spawn( manager, handlerOrderPrimary, [OrderTable, AddrRecord, DroneTable] ),
        Handler ! Msg    % let the new handler apply the order
	

    % Timeout is for the case where the server has no incoming messages for a long period of time,
    % it still has to respond to the ping but the 10 is for preventing aggressive looping of the process
    after
        10 -> true
    end,

    loopPrimary(OrderTable, AddrRecord, DroneTable)
.

loopBackup(OrderTable, AddrRecord, DroneTable, LastPingTime) ->
    Time = erlang:system_time(milli_seconds),
    if
        Time - LastPingTime < 2000  ->
            receive
                %% ping msg case
                {Sender, pingResponse} when Sender == AddrRecord#addr.primaryManagerAddr ->
                    % if the primary responded

                    utils:sendPingLater(self(), AddrRecord#addr.primaryManagerAddr), % send ping after 200 ms
                    CurrentPingTime = 200 + erlang:system_time(milli_seconds),

                    loopBackup(OrderTable, AddrRecord, DroneTable, CurrentPingTime);

                %% other cases
                {newHandler, Pid} -> spawn(manager, handlerOrderBck, [OrderTable, AddrRecord, DroneTable, Pid])

            end;

        true -> io:format("Primary manager not responding: ~w~n", [self()]) % primary not responding
    end
.


%%% handlers %%%

handlerOrderPrimary(OrderTable, AddrRecord, DroneTable) ->
    AddrRecord#addr.bckManagerAddr ! {newHandler, self()},
    % wait for handler of the backup
    receive {bindAdderess, PidBckHandler} -> true
    end,

    % process the msg and bind the variables
    receive { Type, _PidClient, ClientID, OrderID, Description } = Msg
            when Type == makeOrder ; Type == inDelivery ; Type == delivered -> true
    end,

    PidBckHandler ! Msg, % send msg to manager bck and wait confirmation
    receive confirmedBck -> true
    end,

    % handling the order
    if
        Type == makeOrder ->
            {Source, Destination, Weight} = Description, % extract values
            ets:insert(OrderTable, {
                {ClientID, OrderID},
                {Source, Destination, Weight, 0, erlang:system_time(milli_seconds), saved} }
            ),
            % 0 is the default droneID, the time is the last time of the inspection by the manager


            % select random drone
            {DroneID, DroneAddr} = pick_rand(DroneTable),

            PidBckHandler ! DroneID, % send drone choice to the backup
            receive confirmedBck -> true
            end,

            % update table drone
            assignDroneToOrder(OrderTable, {ClientID, OrderID}, DroneID ),

            DroneAddr ! Msg, % we assume the drone is alive, the manager will ping it after a certaint amount of time


            % send confirmation to the broker
            AddrRecord#addr.primaryBrokerAddr !
            {   inProgress,
                {},
                ClientID,
                OrderID,
                {}  % empty description because it's already known by the broker
            }
            ;

        % cases inDelivery and delivered
        true -> updateTableStatus(OrderTable, {ClientID, OrderID}, Type),
                AddrRecord#addr.primaryBrokerAddr !
                {   Type,
                    {},
                    ClientID,
                    OrderID,
                    {}  % empty description because it's already known by the broker
                }

    end
.


handlerOrderBck(OrderTable, AddrRecord, DroneTable, PrimaryHandlerAddr) ->
    PrimaryHandlerAddr ! {bindAdderess, self()},

    % process the msg and bind the variables
    receive { Type, PidClient, ClientID, OrderID, Description }
            when Type == makeOrder ; Type == inDelivery ; Type == delivered -> true
    end,

    if
        Type == makeOrder ->
            {Source, Destination, Weight} = Description, % extract values
            ets:insert(OrderTable, { {ClientID, OrderID}, {Source, Destination, Weight, 0, saved} } ),
            PrimaryHandlerAddr ! confirmedBck,

            receive DroneID -> true
            end,
            assignDroneToOrder(OrderTable, {ClientID, OrderID}, DroneID ),

            PrimaryHandlerAddr ! confirmedBck;

        true -> updateTableStatus(OrderTable, {ClientID, OrderID}, Type),
                PrimaryHandlerAddr ! confirmedBck
    end
.


%%% utils %%%

assignDroneToOrder(OrderTable, Key, DroneID) ->

    {Source, Destination, Weight, _DefoultDroneID, Time, Status} = ets:lookup(OrderTable, Key),
    Result = ets:insert(OrderTable, {Key, {Source, Destination, Weight, DroneID, Time, Status} } ), % overwrite
    if
        Result == false ->
            io:format("Error failed attempt to modify the order table in manager. ~w~n", [{Key, {Source, Destination, Weight, DroneID} }])
    end
.

updateTableStatus(Table, Key, NewStatus) ->
    {Source, Destination, Weight, DroneID, Time, _Status} = ets:lookup(Table, Key),
    Result = ets:insert(Table, {Key, {Source, Destination, Weight, DroneID, Time, NewStatus} } ), % overwrite
    if
        Result == false ->
            io:format("Error failed attempt to modify the order table in manager. ~w~n", [{Key, {Source, Destination, Weight, NewStatus} }])
    end
.



% returns an element of the table (for drone selection in join and election)
pick_rand(Table) ->
    Size = ets:info(Table, size),
    Rand = rand:uniform(Size),
    pick_rand(Table, Rand)
.

pick_rand(Table, N) ->
    if
        N == 1 -> ets:lookup( Table, ets:first(Table) ) ;
        true   -> First = ets:first(Table),
                  pick_rand(Table, First, N-1)
    end
.

pick_rand(Table, Key, N) ->
    if
        N == 0 -> ets:lookup(Table, Key);
        N > 0  -> X = ets:next(Table, Key),
                      pick_rand(Table, X, N-1)
    end
.

create_drone_list(DroneTable, List, Counter, Drone_Address)->
	
	if
		(counter > 0) ->
			New_drone = pick_rand(DroneTable),
			In=lists:member(New_drone, List),
			if (not In) ->
				List ++ New_drone,
				create_drone_list(DroneTable, List, Counter, Drone_Address)
			end,
			create_drone_list(DroneTable, List, Counter - 1, Drone_Address)
	end,
	Drone_Address ! {dronesList, self(), List}
.


