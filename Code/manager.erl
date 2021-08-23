-module(manager).

-export([start/0]).


-export([startPrimary/2, loopPrimary/4, startBck/3, loopBackup/4]).
-export([handlerOrderPrimary/3, handlerOrderBck/4, handlerJoinNetworkPrimary/2, handlerJoinNetworkBck/3]).

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

    OrderTable = ets:new(myTable, [ordered_set, public]),
    DroneTable = ets:new(droneTable, [ordered_set, public]),
    Time = erlang:system_time(seconds),

    loopPrimary(OrderTable, AddrRecord, DroneTable, Time)
.

startBck(Primary, PrimaryBrokerAddr, BckBrokerAddr) ->

    % register bck to primaryBrokerAddr
    Primary ! {self(), addrInit},

    % init data structures
    AddrRecord = #addr{ primaryBrokerAddr = PrimaryBrokerAddr,
                        bckBrokerAddr = BckBrokerAddr,
                        primaryManagerAddr = Primary,
                        bckManagerAddr = self()},

    OrderTable = ets:new(myTable, [ordered_set, public]),
    DroneTable = ets:new(droneTable, [ordered_set, public]),

    AddrRecord#addr.primaryManagerAddr ! ping, % send first ping
    FirstPingTime = erlang:system_time(milli_seconds),

    loopBackup(OrderTable, AddrRecord, DroneTable, FirstPingTime)
.

%%% end init %%%


%%% OrderTable Structure %%%

% key: { ClientID, OrderID }
% value: { Source, Destination, Weight, DroneID, Time, Status }

% DroneID before been set, is also used as counter
% Time is the time of the last status check by the manager

%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%%% processes loops %%%

loopPrimary(OrderTable, AddrRecord, DroneTable, LastCheckTime) ->
    % the ping msg has higher priority
    % the primary server respong immediately, while the backup has some delay to mantain 5 pckt/second
    receive
        {Sender, ping} when Sender == AddrRecord#addr.bckManagerAddr ->
            AddrRecord#addr.bckManagerAddr ! {self(), pingResponse}
    after
       0 -> true
    end,

    % check the status of the orders (failed election, failed drone, ...)
    Time = erlang:system_time(seconds),
    if  % every 3 minutes
        Time - LastCheckTime > (3*60) -> spawn(?MODULE, orderStatusChecker, [OrderTable, DroneTable, Time, AddrRecord]) ;
        true -> true
    end,

    receive

    % DroneTable has key: DroneID, value: DroneAddr

	{joinRequest, _DroneID, _Drone_Address} = Msg ->
	    Handler = spawn(manager, handlerJoinNetworkPrimary, [AddrRecord, DroneTable]),
        Handler ! Msg ;

    % send a single drone new info to the drone requesting it
    % makes two attempt to select a new drone otherwise doesn't reply to the request
    {requestDroneAddr, DroneID, DroneAddr} -> spawn(manager, handlerNewDroneRequest, [DroneTable, DroneID, DroneAddr]) ;


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

    loopPrimary(OrderTable, AddrRecord, DroneTable, Time)
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
                {newHandler, Pid} -> spawn(manager, handlerOrderBck, [OrderTable, AddrRecord, DroneTable, Pid]) ;
                {newHandlerTime, Pid} -> spawn(manager, handlerUpdateTimeOrderBck, [OrderTable, AddrRecord, Pid]) ;
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
                {Source, Destination, Weight, 0, erlang:system_time(milli_seconds), saved} }
            ),
            % 0 for empty droneID, the time is the last time of the inspection by the manager


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
    receive { Type, _PidClient, ClientID, OrderID, Description }
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


% reliably reply with the neighbours drones and save the info
handlerJoinNetworkPrimary(AddrRecord, DroneTable) ->

    AddrRecord#addr.bckManagerAddr ! {newHandlerJoinNetwork, self()},

    % wait for handler of the backup
    receive {bindAdderess, PidBckHandler} -> true
    end,

    receive {joinRequest, DroneID, Drone_Address} = Msg -> true
    end,

    PidBckHandler ! Msg,

    receive confirmedBck -> true
    end,

    List = create_drone_list(DroneTable), % only addresses of the drones, no IDs
    Drone_Address ! {droneList, List},

    % store it
    ets:insert( DroneTable, {DroneID, Drone_Address} )
.

handlerJoinNetworkBck(AddrRecord, DroneTable, PrimaryHandlerAddr) ->

    PrimaryHandlerAddr ! {bindAdderess, self()}, % meet the primary

    receive {joinRequest, DroneID, Drone_Address} -> true
    end,

    % store it
    ets:insert( DroneTable, {DroneID, Drone_Address} ),

    PrimaryHandlerAddr ! confirmedBck  % send confirmation
.

% makes two attempt to select a new drone otherwise doesn't reply to the request
handlerNewDroneRequest(DroneTable, DroneID, DroneAddr) ->

	{NewDroneID, NewDroneAddr} = pick_rand(DroneTable),
    {NewDroneID2, NewDroneAddr2} = pick_rand(DroneTable),

    if
    NewDroneID  /= DroneID -> DroneAddr ! {newDrone, NewDroneAddr};
    NewDroneID2 /= DroneID -> DroneAddr ! {newDrone, NewDroneAddr2};
    true -> true
    end
.


handlerUpdateTimeOrderPrimary(OrderTable, AddrRecord, Key, Time) ->
    AddrRecord#addr.bckManagerAddr ! {newHandlerTime, self()},
    % wait for handler of the backup
    receive {bindAdderess, PidBckHandler} -> true
    end,

    PidBckHandler ! {Key, Time},
    receive confirmedBck -> true
    end,

    updateTableTime(OrderTable, Key, Time)
.

handlerUpdateTimeOrderBck(OrderTable, AddrRecord, PrimaryHandlerAddr) ->
    PrimaryHandlerAddr ! {bindAdderess, self()},

    receive {Key, Time} -> true
    end,

    updateTableTime(OrderTable, Key, Time),

    PrimaryHandlerAddr ! confirmedBck
.

% this function trys to check and solve the blocked orders
orderStatusChecker(OrderTable, DroneTable, CurrentTime, ManagerAddr, AddrRecord) ->

    CheckSingleOrder =
        fun(Order) ->
            { {ClientID, OrderID} , {Source, Destination, Weight, DroneID, Time, Status} } = Order,
            % DroneID also used as counter

            TimeDifference = Time - CurrentTime,

            if
                (Status == excessiveWeight and TimeDifference) > 3*60 ->
                if
                   % if the manager tried less then 3 times
                    DroneID > -2 -> % DroneID also used as inverted counter 0, -1, -2
                    % update status only in primary, for semplicity
                    ets:insert(OrderTable, {ClientID, OrderID} , {Source, Destination, Weight, DroneID-1, Time, Status} ),
                    spawn(manager, handlerUpdateTimeOrderPrimary, [OrderTable, AddrRecord, {ClientID, OrderID}, CurrentTime]) ;

                    true -> io:format("Order failed 3 times due to excessive weight. Client:~w, Order:~w, Weight:~w~n", [ ClientID, OrderID, Weight ])

                end ;

                (Status == inDelivery and TimeDifference) > 15*60 ->
                % ping drone, if fails alert
                    DroneAddr = ets:lookup(DroneTable, DroneID),
                    DroneAddr ! {droneStatus, self()},
                    receive {droneStatus, _, _ } -> true
                    after 10*1000 -> io:format("Drone offline Drone:~w, Client:~w, Order:~w, Weight:~w~n", [ DroneID, ClientID, OrderID, Weight ])
                    end ;

                (Status == inProgress and TimeDifference) > 15*60 ->
                % we assume the election is finished ( unforeseen situation possible )
                % recreation of the order, that will be fed to the main process of the manager.
                % no need to update time nor status of the order
                ManagerAddr ! {makeOrder, {}, ClientID, OrderID, {Source, Destination, Weight} }

            end

    end,

    lists:map( CheckSingleOrder, ets:tab2list(OrderTable) ) % not efficient
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
            io:format("Error failed attempt to update the order table in manager. ~w~n", [{Key, {Source, Destination, Weight, NewStatus} }])
    end
.

updateTableTime(Table, Key, NewTime) ->
    {Source, Destination, Weight, DroneID, _Time, Status} = ets:lookup(Table, Key),
    Result = ets:insert(Table, {Key, {Source, Destination, Weight, DroneID, NewTime, Status} } ), % overwrite

    if
        Result == false ->
            io:format("Error failed attempt to update time the order table in manager. ~w~n", [{Key, {Source, Destination, Weight, Status} }])
    end
.



% returns a single element of the table (for drone selection in join and election)
pick_rand(Table) ->
    Size = ets:info(Table, size),
    Rand = rand:uniform(Size),
    pick_rand(Table, Rand)
.

pick_rand(Table, N) ->
    if
        N == 1 -> [Elem] = ets:lookup( Table, ets:first(Table) ), Elem ;
        true   -> First = ets:first(Table),
                  pick_rand(Table, First, N-1)
    end
.

pick_rand(Table, Key, N) ->
    if
        N == 0 -> [Elem] = ets:lookup(Table, Key), Elem;
        N  > 0 -> X = ets:next(Table, Key),
                  pick_rand(Table, X, N-1)
    end
.


% return the list of drone addresses (3 elements) that has to be send to the new drone
create_drone_list(DroneTable) ->
    Size = ets:info(DroneTable, size),
	ListID = case Size of
		      0 -> [] ;
		      1 -> [ets:first(DroneTable)] ;
		      2 -> First = ets:first(DroneTable), Second = ets:next(DroneTable, First), [First, Second];
		      3 -> First = ets:first(DroneTable), Second = ets:next(DroneTable, First),
		           Third = ets:next(DroneTable, Second), [First, Second, Third];

		      _Other -> create_drone_list_aux(DroneTable, [], 3)
		   end,
	% first() and next() works on keys
	% extract the addresses
	mapLookup(DroneTable, ListID)
.

% take key list return Value list
mapLookup(Table, KeyList) ->
    io:format("keylist: ~w~n", [KeyList]),
    case KeyList of
    []      ->  [];
    [X|Xs]  ->  [{_Key, Value}] = ets:lookup(Table, X), % extract the value
                [ Value | mapLookup(Table, Xs)]
    end
.

create_drone_list_aux(DroneTable, List, Counter)->
	if
	    Counter == 0 -> List ;
		Counter  > 0 ->
			New_drone = pick_rand(DroneTable),
			{Key, _Value} = New_drone,
			IsMember = lists:member(Key, List),

			if
			    (not IsMember) -> create_drone_list_aux(DroneTable, [Key | List] , Counter-1) ;
			    IsMember       -> create_drone_list_aux(DroneTable, List, Counter)
			end
	end
.


