%% @author Andrea
%% @doc @todo Add description to drone.


-module(drone).

-compile(export_all).

%-export([start/5]).
%-export([connect_to_drones/5, requestNewDrone/6, checkNeighbour/5, drone_Loop/8]).

-define(BATTERY_CAPACITY, 500).     % NEED TO BE INT ! battery expressed as remaining distance
-define(RECHARGE_SPEED, 1).         % NEED TO BE INT ! seconds needed to recharge the power equivalent to 1 move
-define(CONSTANT_MOVEMENT, 100).    % NEED TO BE INT ! default 1000

start(Manager_Server_Addr, DroneID, SupportedWeight, DronePosition, RechargingStations) ->

    ElectionTable = ets:new(electionTable, [set, public]),
    % table for elections in progress, the messages received by the drone relative to an election in progress are sent to the
    % correct handler for the election

	Pid = spawn(drone, drone_Loop,
	               [
	                    Manager_Server_Addr,
	                    DroneID,
	                    [],                     % list of neighbours
	                    SupportedWeight,
	                    DronePosition,
	                    ?BATTERY_CAPACITY,
	                    RechargingStations,     % list of position for recharging station
	                    idle,                   % status of the drone
	                    0,                      % counter for refused election due to low power, after 3 go to recharge station
	                    ElectionTable
	               ]
	           ),

	Manager_Server_Addr ! { joinRequest, DroneID, Pid },

	timer:sleep(infinity) % needed for mantaing the existence of the table
.


drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, DronePosition,
            DroneBattery, RechargingStations, DroneStatus, LowBatteryCounter, ElectionTable) ->
% NeighbourList is only addresses

% there is an exit at the bottom for cases without state modification

	receive

%%%%%% messages relative to drone status %%%%%%%%%%%%%

		% receive the drone list to connect to, form manager
		{droneList, DronesList} ->
			 NewNeighbourList = connect_to_drones(DronesList, [], DroneID, self(), Manager_Server_Addr),

			 case NewNeighbourList of
			 []     -> timer:sleep(1000), Manager_Server_Addr ! { joinRequest, DroneID, self() } ;
			 _Other -> skip
			 end,
			 io:format("Drone ~w, PID ~w, List : ~w~n", [DroneID, self(), NewNeighbourList]),
			 drone_Loop(Manager_Server_Addr, DroneID, NewNeighbourList, SupportedWeight, DronePosition, DroneBattery,
			            RechargingStations, DroneStatus, LowBatteryCounter, ElectionTable);


		% receive a request for connection from another drone, add it if it was unknown
		{connection, NeighbourDroneAddr} ->
			NeighbourDroneAddr ! confirmConnection,

			% avoid inserting duplicates
			Condition = lists:member(NeighbourDroneAddr, NeighbourList),
			if
			Condition == false ->
			    io:format("Drone ~w, PID ~w, List : ~w~n", [DroneID, self(), NeighbourList ++ [NeighbourDroneAddr]]),
			    drone_Loop(Manager_Server_Addr, DroneID, NeighbourList ++ [NeighbourDroneAddr], SupportedWeight,
			                DronePosition, DroneBattery, RechargingStations, DroneStatus, LowBatteryCounter, ElectionTable) ;

			Condition == true -> true   % exit at bottom
			end;

        % receive the list of online drones from the auxiliary process
        {newList, OnlineDrones} -> drone_Loop(Manager_Server_Addr, DroneID, OnlineDrones, SupportedWeight, DronePosition,
                                            DroneBattery, RechargingStations, DroneStatus, LowBatteryCounter, ElectionTable) ;

        % receive a query from an other drone
        {queryOnline, DroneAddr} -> DroneAddr ! online ; % exit at bottom

		% receive a drone status query from manager (or shell)
		{droneStatus, Manager_Server_Addr} ->
			Manager_Server_Addr ! {droneStatus, self(), DroneID, DronePosition, DroneBattery, DroneStatus} ; % exit at bottom

		{newPosition, NewPosition} -> drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, NewPosition,
                                        DroneBattery, RechargingStations, DroneStatus, LowBatteryCounter, ElectionTable) ;

		lowBattery ->
		    if
		    LowBatteryCounter == -1 -> true; % in case the drone is already going to recharge
		    LowBatteryCounter < 2   -> drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight,
		                                DronePosition, DroneBattery, RechargingStations, DroneStatus, LowBatteryCounter + 1, ElectionTable) ;
		    true -> io:format("Drone ~w going to recharge.~n", [DroneID]),
		            spawn(drone, goToRecharge, [self(), DroneBattery, DronePosition, RechargingStations]),
		            drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, DronePosition, DroneBattery,
			            RechargingStations, charging, -1, ElectionTable)
		    end ;


        {modifyBatteryCharge, BatteryUsed} -> drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight,
                                DronePosition, DroneBattery - BatteryUsed, RechargingStations, DroneStatus, LowBatteryCounter, ElectionTable ) ;


        rechargeCompleted -> io:format("Recharge completed~n"),
			drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight,
                                DronePosition, ?BATTERY_CAPACITY, RechargingStations, idle, 0, ElectionTable ) ;

%        crashOnline ->  if
%                        DroneStatus == idle or DroneStatus == recharging -> io:format("crashOnline drone: ~w.~n", [DroneID]),
%                                                                            exit("crashOnline") ;

%                        DroneStatus == {delivering, _ClientID, _OrderID, _Source, _Destination, _Weight } ->
%                            HandlerCrash(NeighbourList)
%                       end;

        crashOffline -> io:format("crashOffline drone: ~w.~n", [DroneID]),
                        exit("crashOffline") ;

%%%%%% messages relative to orders %%%%%%%%%%%%%

		{ makeOrder, _PidClient, ClientID, OrderID, _Description } = Msg ->
			InitElection = spawn(election, initElection, [self(), DroneID, SupportedWeight, DronePosition, DroneBattery,
			                         NeighbourList, RechargingStations, DroneStatus]),
			ets:insert(ElectionTable, { {ClientID, OrderID}, InitElection }),   % save info election in progress
			InitElection! Msg ; % exit at bottom



		{elected, ClientID, OrderID, Source, Destination, Weight} ->
			io:format("Drone ~w has been elected.~n", [DroneID]),

			Manager_Server_Addr ! {inDelivery, DroneID, ClientID, OrderID, {}}, % notify the manager
            spawn(drone, droneDelivery, [self(), DronePosition, Source, Destination, ClientID, OrderID]),
            drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, DronePosition, DroneBattery,
			            RechargingStations, {delivering, ClientID, OrderID, Source, Destination, Weight }, LowBatteryCounter, ElectionTable) ;

        % notify manager and free drone
        {delivered, ClientID, OrderID} ->
            spawn(drone, notifyManager, [Manager_Server_Addr, ClientID, OrderID]),
            io:format("Package number ~w from ~w delivered~n", [OrderID, ClientID]),
            drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, DronePosition, DroneBattery,
			            RechargingStations, idle, LowBatteryCounter, ElectionTable) ; % drone now free

		% check that all the neighbours are alive, remove dead, if <= 2 ask more to manager
		electionFailed ->
		    spawn(drone, checkNeighbour, [NeighbourList, [], DroneID, self(), Manager_Server_Addr]); % exit at bottom


		{excessiveWeight, ClientID, OrderID, Weight} ->
			io:format("~n the package ~w from ~w weighs too much: ~w~n", [OrderID, ClientID, Weight]); % exit at bottom


%%%%%% messages for the elelections in progress %%%%%%

		{election, Addr, ClientID, OrderID, {Source, Destination, Weight} } = Wave ->
            % in the case the wave for a particular election is the first, create a new handler,
            % otherwise turn the message to the previous handler
		    case ets:lookup(ElectionTable, {ClientID, OrderID}) of
		    [] ->   Handler = spawn(election,
		                nonInitElection,
		                [self(), DroneID, SupportedWeight, DronePosition, DroneBattery, NeighbourList, RechargingStations, DroneStatus]
		            ),
		            ets:insert( ElectionTable, { {ClientID, OrderID} , Handler }) ;
		    [{_Key, Handler}] -> true
		    end,

		    Handler ! Wave ;

		{result, _ElectedDroneID, _ElectedPid, _Distance, {ClientID, OrderID} } = Msg ->
		    case ets:lookup(ElectionTable, {ClientID, OrderID}) of
		    [] -> io:format("Error in election, received a result messages without election. ~n") ;
		    [{_Key, Handler}] -> Handler ! Msg
		    end

	end,

	% NORMAL EXIT WITHOUT STATE MODIFICATION
	drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, DronePosition, DroneBattery,
			            RechargingStations, DroneStatus, LowBatteryCounter, ElectionTable)
.


%% ====================================================================
%% Internal functions
%% ====================================================================

droneDelivery(DroneAddr, DronePosition, Source, Destination, ClientID, OrderID) ->

	{P1,P2} = DronePosition,
	{S1,S2} = Source,
    {D1,D2} = Destination,

    % trunc for converting to int
    DistanceToPackage = trunc(math:ceil(math:sqrt( math:pow( P1-S1, 2 ) + math:pow( P2-S2, 2 )))),
    DistanceOfDelivery = trunc(math:ceil(math:sqrt( math:pow( S1-D1, 2 ) + math:pow( S2-D2, 2 )))),

	io:format("DronePosition: ~w~nDistanceToPackage: ~w~nDistanceOfDelivery: ~w~n", [DronePosition, DistanceToPackage, DistanceOfDelivery]),

    % since speed is 1 per second, Distance is also time to wait
    timer:sleep(DistanceToPackage * ?CONSTANT_MOVEMENT),

    DroneAddr ! {newPosition, Source}, % notify drone, that will change position
    DroneAddr ! {modifyBatteryCharge, DistanceToPackage},

    timer:sleep(DistanceOfDelivery * ?CONSTANT_MOVEMENT),

    DroneAddr ! {newPosition, Destination},                 % notify new position
    DroneAddr ! {modifyBatteryCharge, DistanceOfDelivery }, % pass the battery level to subctract
    DroneAddr ! {delivered, ClientID, OrderID}              % notify order completed

.

goToRecharge(DroneAddr, DroneBattery, DronePosition, RechargingStations) ->

	{P1,P2} = DronePosition,

	if
		length(RechargingStations) == 0 ->
			io:format("Error: There are no recharging stations~n") ;
		true ->
			Distances = lists:map(
        	    fun(Station) -> {S1, S2} = Station, math:sqrt( math:pow( S1-P1, 2 ) + math:pow( S2-P2, 2 ) ) end,
        	    % end lambda func
        	    RechargingStations     % list for the map
        	),

   			Min = lists:min(Distances),
   			MinIndex = index_of(Min, Distances),

   			RecStation = lists:nth(MinIndex, RechargingStations),

   		    Distance = trunc(math:ceil(Min)), % trunc for converting to int

   		    io:format("Drone going to Station: ~w, from: ~w, distance: ~w~n", [RecStation, DronePosition, Distance]),

   		    % since speed is 1 per second, Distance is also time to wait
            timer:sleep(Distance * ?CONSTANT_MOVEMENT ),
            DroneAddr ! {modifyBatteryCharge, Distance}, % pass the battery level to subctract
            DroneAddr ! {newPosition, RecStation},       % notify new position


            io:format("Drone in recharge~n"),

            RemainingBattery = DroneBattery - Distance,
            if
		        RemainingBattery < 0 -> io:format("Remaining battery negative ~w~n",[RemainingBattery]);

    	        true -> timer:sleep( (?BATTERY_CAPACITY - RemainingBattery) * 1000 * ?RECHARGE_SPEED )
	        end,

            DroneAddr ! rechargeCompleted

	end
.


index_of(Item, List) -> index_of(Item, List, 1).

index_of(_, [], _)  -> not_found;
index_of(Item, [Item|_], Index) -> Index;
index_of(Item, [_|Tl], Index) -> index_of(Item, Tl, Index+1).


% notify manager and await for confirmation
notifyManager(Manager_Server_Addr, ClientID, OrderID) ->
    Manager_Server_Addr ! {delivered, self(), ClientID, OrderID, {}},
    receive confirmDelivered -> ok
    after 3000 -> notifyManager(Manager_Server_Addr, ClientID, OrderID)
    end
.


% take a list of drones to connect to, in case of failure ask for new drone addresses to the manager
% return the list of online and connected drones
connect_to_drones(DronesList, DronesAlreadyConnectedTo, MyDroneID, MyDroneAddr, ManagerAddr)->
    case DronesList of
        []     ->   DronesAlreadyConnectedTo ;
        [X|Xs] ->
            if
            % avoid self connection
            X == MyDroneAddr -> connect_to_drones(Xs, DronesAlreadyConnectedTo, MyDroneID, MyDroneAddr, ManagerAddr) ;

            true -> X ! {connection, MyDroneAddr},

                    % receive confirmation from the other drone
                    receive confirmConnection -> NewDrone = X
                    after % in case of timeout consider the drone dead and send a request to the manager for a single new drone
				    2000 -> NewDrone = requestNewDrone(DronesList, DronesAlreadyConnectedTo, MyDroneID, MyDroneAddr, ManagerAddr, 3)
                    % requestNewDrone() asks the manager a single drone; after the reply,
                    % it checks that the drone it's not connected to the new candidate drone or is already in the candidates.
                    % we also prevent the send of the faulty drone check before passing to the function DronesList inseted of Xs
                    % the manager doesn't reply with the drone that made the request, so no check of self connect attempt
                    % is needed here

                    end,

                    % if requestNewDrone() fails due to probabilitic reason, it returns {}
				    if
				        % procede with the connection to the next drones ignoring the failure
					    NewDrone == {} ->
						    connect_to_drones(Xs, DronesAlreadyConnectedTo, MyDroneID, MyDroneAddr, ManagerAddr) ;
						% correct exit
					    true -> connect_to_drones(Xs, [NewDrone | DronesAlreadyConnectedTo ], MyDroneID, MyDroneAddr, ManagerAddr)
				    end
			end
    end
.


% returns the new drone address or {} in case of failure. It will make "Counter" attempt.
requestNewDrone(DronesCandidateToConnection, DronesAlreadyConnectedTo, MyDroneID, MyDroneAddr, ManagerAddr, Counter)->
	if
	Counter > 0 ->
        ManagerAddr ! {requestDroneAddr, MyDroneID, MyDroneAddr},

		receive {newDrone, _NewDroneID, NewDroneAddr} ->
	    	case lists:member( NewDroneAddr, DronesCandidateToConnection ++ DronesAlreadyConnectedTo) of
			 true -> requestNewDrone(DronesCandidateToConnection, DronesAlreadyConnectedTo, MyDroneID, MyDroneAddr, ManagerAddr, Counter-1);
			 false -> NewDroneAddr
			 end
		after 2000 -> {}
		end ;

	% in case of "Counter" failed attempt
	Counter == 0 -> {}
	end
.


% take a list of Neighbour drones, in case of failure or timeout remove them, if the list becomes <2 ask for new drones addresses to the manager
% return with a message to the main process the list of online drones

% check that all the neighbours are alive, remove dead, if < 2 ask more to manager
checkNeighbour(NeighbourList, OnlineDrones, MyDroneID, MyDroneAddr, ManagerAddr) ->

    case NeighbourList of

        [X|Xs] ->   if
					X=={}  -> 	MyDroneAddr ! {newList, OnlineDrones};

					true->	X ! {queryOnline, MyDroneAddr},

                   		receive online -> checkNeighbour(Xs, OnlineDrones ++ [X], MyDroneID, MyDroneAddr, ManagerAddr)
                   		after % in case of timeout consider the drone dead, don't add it to online list
				   		2000 -> checkNeighbour(Xs, OnlineDrones, MyDroneID, MyDroneAddr, ManagerAddr)
                   		end
					end;
	    []     ->
		   		Len = length(OnlineDrones),
				if
				    Len < 2 ->  NewDrone = requestNewDrone(NeighbourList, OnlineDrones, MyDroneID, MyDroneAddr, ManagerAddr, 0),
					            checkNeighbour(NeighbourList ++ [NewDrone], OnlineDrones, MyDroneID, MyDroneAddr, ManagerAddr) ;
					true ->     MyDroneAddr ! {newList, OnlineDrones}
				end
	end
.
