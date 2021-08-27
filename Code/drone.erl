%% @author Andrea
%% @doc @todo Add description to drone.


-module(drone).

-compile(export_all).

%-export([start/5]).
%-export([connect_to_drones/5, requestNewDrone/6, checkNeighbour/5, drone_Loop/8]).


start(Manager_Server_Addr, DroneID, SupportedWeight, DronePosition, RechargingStations) ->

	Pid = spawn(drone, drone_Loop,
	               [
	                    Manager_Server_Addr,
	                    DroneID,
	                    [],                     % list of neighbours
	                    SupportedWeight,
	                    DronePosition,
	                    500,                    % battery expressed as remaining distance
	                    RechargingStations,     % list of position for recharging station
	                    idle                    % status of the drone
	               ]
	           ),

	Manager_Server_Addr ! { joinRequest, DroneID, Pid }
.


drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, DronePosition,
            DroneBattery, RechargingStations, DroneStatus) ->
% NeighbourList is only addresses

	receive

%%%%%% messages relative to drone status %%%%%%%%%%%%%

		% receive the drone list to connect to, form manager
		{droneList, DronesList} ->
			 NewNeighbourList = connect_to_drones(DronesList, [], DroneID, self(), Manager_Server_Addr),

			 case NewNeighbourList of
			 []     -> timer:sleep(1000), Manager_Server_Addr ! { joinRequest, DroneID, self() } ;
			 _Other -> skip
			 end,
			 io:format("Drone ~w, ID ~w, List : ~w~n", [DroneID, self(), NewNeighbourList]),
			 drone_Loop(Manager_Server_Addr, DroneID, NewNeighbourList, SupportedWeight, DronePosition, DroneBattery,
			            RechargingStations, DroneStatus);


		% receive a request for connection from another drone
		{connection, NeighbourDroneAddr} ->
			NeighbourDroneAddr ! confirmConnection,

			% avoid inserting duplicates
			Condition = lists:member(NeighbourDroneAddr, NeighbourList),
			if
			Condition == false ->
			    io:format("Drone ~w, ID ~w, List : ~w~n", [DroneID, self(), NeighbourList ++ [NeighbourDroneAddr]),
			    drone_Loop(Manager_Server_Addr, DroneID, NeighbourList ++ [NeighbourDroneAddr], SupportedWeight,
			                DronePosition, DroneBattery, RechargingStations, DroneStatus ) ;

			Condition == true -> drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight,
			                        DronePosition, DroneBattery, RechargingStations, DroneStatus)
			end;

        % receive the list of online drones from the auxiliary process
        {newList, OnlineDrones} -> drone_Loop(Manager_Server_Addr, DroneID, OnlineDrones, SupportedWeight, DronePosition,
                                            DroneBattery, RechargingStations, DroneStatus) ;

        % receive a query from an other drone
        {queryOnline, DroneAddr} -> DroneAddr ! online ;

		% receive a drone status query from manager !! NEED TO EXPAND !!
		{droneStatus, Manager_Server_Addr} ->
			Manager_Server_Addr ! {droneStatus, self(), DroneID, DroneStatus},
			drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, DronePosition, DroneBattery,
			            RechargingStations, DroneStatus) ;

		{newPosition, NewPosition} -> drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, NewPosition,
                                        DroneBattery, RechargingStations, DroneStatus) ;


%%%%%% messages relative to orders %%%%%%%%%%%%%

		% check that all the neighbours are alive, remove dead, if <= 2 ask more to manager
		{electionFailed} ->
		    spawn(drone, checkNeighbour, [NeighbourList, [], DroneID, self(), Manager_Server_Addr]),
			drone_Loop(Manager_Server_Addr, DroneID, NewNeighbourList, SupportedWeight, DronePosition, DroneBattery,
			            RechargingStations, DroneStatus);

		% initElection(DroneAddr, DroneID, DroneCapacity, DronePosition, DroneBattery, Neighbours, RechargingStations)
		{ makeOrder, PidClient, ClientID, OrderID, Description } = Msg ->

			io:format("~n about to start election: ~n"),
			InitElection = spawn(election, initElection, [self(), DroneID, SupportedWeight, DronePosition, DroneBattery,
			                         NeighbourList, RechargingStations]),
			InitElection! Msg,
			drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, DronePosition, DroneBattery,
			                 RechargingStations, DroneStatus);

		{excessiveWeight, ClientID, OrderID} ->
			io:format("~n the package weighs too much: ~n"),
			drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, DronePosition, DroneBattery,
			            RechargingStations, DroneStatus);

		{elected, ClientID, OrderID, Source, Destination } ->
			Manager_Server_Addr ! {inDelivery, DroneID, ClientID, OrderID, {}}, % notify the manager
            spawn(drone, droneDelivery, [self(), DronePosition, Source, Destination, ClientID, OrderID]),
            drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, DronePosition, DroneBattery,
			            RechargingStations, busy) ;


		{lowBattery} ->
			RecStation = election:findNearestRechargingStation(DronePosition, RechargingStations),
			{D1,D2} = RecStation,
			{S1,S2} = DronePosition,
			Wait = (math:sqrt( math:pow( D1-S1, 2 ) + math:pow( D2-S2, 2 )) + 100 ), % 100 standard time the drone spends at the recharging station to fully recharge
			drone_Loop_Busy(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, DronePosition, DroneBattery,
			                RechargingStations, recharging, Wait, RecStation, 0, 0)



	end
.


%% ====================================================================
%% Internal functions
%% ====================================================================

droneDelivery(DroneAddr, DronePosition, Source, Destination, ClientID, OrderID) ->

	{P1,P2} = DronePosition,
	{S1,S2} = Source,
    {D1,D2} = Destination,

    % round for excess
    DistanceToPackage = math:ceil(math:sqrt( math:pow( P1-S1, 2 ) + math:pow( P2-S2, 2 ))),
    DistanceOfDelivery = math:ceil(math:sqrt( math:pow( S1-D1, 2 ) + math:pow( S2-D2, 2 ))),

    % since speed is 1 per second, Distance is also time to wait
    timer:sleep(DistanceToPackage *1000),

    DroneAddr ! {newPosition, Source} % notify drone, that will change position

    timer:sleep(DistanceOfDelivery *1000),

    DroneAddr ! {newPosition, Destination}
.


drone_Loop_Busy(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight,
                DronePosition, DroneBattery, RechargingStations, DroneStatus, Wait, Dest, ClientID, OrderID) ->
	receive
		{droneStatus, Manager_Server_Addr} ->
			Manager_Server_Addr ! {droneStatus, self(), DroneID, DroneStatus};

		{ election, ElectionAddr, ClientID, OrderID, {Source, Destination, Weight} } ->
			ElectionAddr!msg
	end,
	timer:sleep(Wait),
	case DroneStatus of
		inDelivery -> drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, Dest, DroneBattery-round((Wait/10)), RechargingStations, idle), Manager_Server_Addr!{delivered,0, ClientID, OrderID, 0 };
		recharging -> drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, Dest, 100, RechargingStations, idle)
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

        [X|Xs] ->   X ! {queryOnline, MyDroneAddr},

                    receive online -> checkNeighbour(Xs, OnlineDrones ++ [X], MyDroneID, MyDroneAddr, ManagerAddr)
                    after % in case of timeout consider the drone dead, don't add it to online list
				    2000 -> checkNeighbour(Xs, OnlineDrones, MyDroneID, MyDroneAddr, ManagerAddr)
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
