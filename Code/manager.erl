-module(manager).

-export([start/0]).


-export([startPrimary/2, loopPrimary/3, startBck/3, loopBackup/4]).
-export([handlerOrderPrimary/3, handlerOrderBck/4, handlerJoinNetworkPrimary/2, handlerJoinNetworkBck/3]).
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

    % DroneTable has key: DroneID, value: DroneAddr

	{joinRequest, _Drone_Address, _DroneID, {}, _Weight} = Msg ->
	    Handler = spawn(manager, handlerJoinNetworkPrimary, [AddrRecord, DroneTable]),
        Handler ! Msg ;

    %{requestDroneAddr, DroneAddr, DroneID} -> % send a single drone new info to the drone requesting it


    % receive make order, save, reply to broker with inProgress, select random drone
    % receive inDelivery (means elected) from a drone, save info and new status, inform the broker
    % receive delivered from a drone, save info and new status, inform the broker
    { Type, _Client_or_Drone_Address, _ClientID, _OrderID, _Description } = Msg
    when Type == makeOrder ; Type == inDelivery ; Type == inProgress ; Type == excessiveWeight ->
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
                {newHandler, Pid} -> spawn(manager, handlerOrderBck, [OrderTable, AddrRecord, DroneTable, Pid]);
                {newHandlerJoinNetwork, Pid} -> spawn(manager, handlerJoinNetworkBck, [AddrRecord, DroneTable, Pid])

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
                {Source, Destination, Weight, 0, erlang:system_time(seconds), saved} }
            ),
            % 0 for empty droneID, the time is the last time of the inspection by the manager, not last modification


            % select random drone
            {DroneID, DroneAddr} = pick_rand(DroneTable),

            PidBckHandler ! DroneID, % send drone choice to the backup
            receive confirmedBck -> true
            end,

            % update table drone
            assignDroneToOrder(OrderTable, {ClientID, OrderID}, DroneID ),

            DroneAddr ! Msg, % we assume the drone is alive, the manager will ping it after a certaint amount of time


            % send confirmation to the broker, it means that the order has been saved
            AddrRecord#addr.primaryBrokerAddr !
            {   inProgress,
                {},
                ClientID,
                OrderID,
                {}  % empty description because it's already known by the broker
            }
            ;

        Type == excessiveWeight -> updateTableStatus(OrderTable, {ClientID, OrderID}, Type),
                                   updateTableTime(OrderTable, {ClientID, OrderID})

        % cases inDelivery and delivered
        true -> updateTableStatus(OrderTable, {ClientID, OrderID}, Type),

                AddrRecord#addr.primaryBrokerAddr ! % send to broker
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
    receive { Type, _PidClient, ClientID, OrderID, Description }
            when Type == makeOrder ; Type == inDelivery ; Type == delivered -> true
    end,

    if
        Type == makeOrder ->
            {Source, Destination, Weight} = Description, % extract values
            ets:insert(OrderTable, { {ClientID, OrderID}, {Source, Destination, Weight, 0, erlang:system_time(seconds), saved} } ),
            PrimaryHandlerAddr ! confirmedBck,

            receive DroneID -> true
            end,
            assignDroneToOrder(OrderTable, {ClientID, OrderID}, DroneID ),

            PrimaryHandlerAddr ! confirmedBck;

        true -> updateTableStatus(OrderTable, {ClientID, OrderID}, Type),
                PrimaryHandlerAddr ! confirmedBck
    end
.


% reliably reply with the neighbours drones and save the info
handlerJoinNetworkPrimary(AddrRecord, DroneTable) ->

    AddrRecord#addr.bckManagerAddr ! {newHandlerJoinNetwork, self()},

    % wait for handler of the backup
    receive {bindAdderess, PidBckHandler} -> true
    end,

    receive {joinRequest, Drone_Address, DroneID, _, _Weight} -> true
    end,

    PidBckHandler ! {joinRequest, Drone_Address, DroneID, self(), Weight},

    receive confirmedBck -> true
    end,

    % store it
    ets:insert( DroneTable, {DroneID, Drone_Address} ),

    List = create_drone_list(DroneTable),

    Drone_Address ! List
.

handlerJoinNetworkBck(AddrRecord, DroneTable, PrimaryHandlerAddr) ->

    PrimaryHandlerAddr ! {bindAdderess, self()}, % meet the primary

    receive {joinRequest, Drone_Address, DroneID, PrimaryHandlerAddr, _Weight} -> true
    end,

    % store it
    ets:insert( DroneTable, {DroneID, Drone_Address} ),

    PrimaryHandlerAddr ! confirmedBck  % send confirmation
.

%%% utils %%%

assignDroneToOrder(OrderTable, Key, DroneID) ->

    {Source, Destination, Weight, _DefoultDroneID, Time, Status} = ets:lookup(OrderTable, Key),
    Result = ets:insert(OrderTable, {Key, {Source, Destination, Weight, DroneID, Time, Status} } ), % overwrite
    if
        Result == false ->
            io:format("Error failed attempt to assign the drone in the order table in manager. ~w~n", [{Key, {Source, Destination, Weight, DroneID} }])
    end
.

updateTableStatus(Table, Key, NewStatus) ->
    {Source, Destination, Weight, DroneID, Time, _Status} = ets:lookup(Table, Key),
    Result = ets:insert(Table, {Key, {Source, Destination, Weight, DroneID, Time, NewStatus} } ), % overwrite
    if
        Result == false ->
            io:format("Error failed attempt to update the order table in manager. ~w~n", [{Key, {Source, Destination, Weight, NewStatus} }])
    end
.

updateTableTime(Table, Key) ->
    {Source, Destination, Weight, DroneID, _Time, Status} = ets:lookup(Table, Key),
    NewTime = erlang:system_time(seconds),
    Result = ets:insert(Table, {Key, {Source, Destination, Weight, DroneID, NewTime, Status} } ), % overwrite

    if
        Result == false ->
            io:format("Error failed attempt to update time the order table in manager. ~w~n", [{Key, {Source, Destination, Weight, NewStatus} }])
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
        N  > 0 -> X = ets:next(Table, Key),
                      pick_rand(Table, X, N-1)
    end
.


% return the list that has to be send to the new drone
create_drone_list(DroneTable) ->
    Size = ets:info(DroneTable, size),
	List = case Size of
		      0 -> [] ;
		      1 -> ets:first(DroneTable);
		      2 -> First = ets:first(DroneTable), Second = ets:next(DroneTable, First), [First, Second];
		      3 -> First = ets:first(DroneTable), Second = ets:next(DroneTable, First),
		           Third = ets:next(DroneTable, Second), [First, Second, Third];

		      _Other -> create_drone_list_aux(DroneTable, [], Size)
		   end,
	List
.

create_drone_list_aux(DroneTable, List, Counter)->
	if
	    Counter == 0 -> List ;
		Counter  > 0 ->
			New_drone = pick_rand(DroneTable),
			IsMember = lists:member(New_drone, List),

			if
			    (not IsMember) -> create_drone_list_aux(DroneTable, [New_drone | List] , Counter-1);
			    IsMember       -> create_drone_list_aux(DroneTable, List, Counter)
			end
	end
.


