%% @author Andrea
%% @doc @todo Add description to drone.


-module(drone).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start/5]).
-export([connect_to_drones/5, requestNewDrone/6, checkNeighbour/5, drone_Loop/8]).


start(Manager_Server_Addr, DroneID, SupportedWeight, DronePosition, RechargingStations) ->
    
	Pid= spawn(drone, drone_Loop, [Manager_Server_Addr, DroneID, [], SupportedWeight, DronePosition, 100, RechargingStations, idle]),
	Manager_Server_Addr ! { joinRequest, DroneID, Pid }
.


drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, DronePosition, DroneBattery, RechargingStations, DroneStatus) -> % NeighbourList is only addresses

	receive

		% receive the drone list to connect to, form manager
		{dronesList, DronesList} ->
			 NewNeighbourList = connect_to_drones(DronesList, [], DroneID, self(), Manager_Server_Addr),
			 drone_Loop(Manager_Server_Addr, DroneID, NewNeighbourList, SupportedWeight, DronePosition, DroneBattery, RechargingStations, DroneStatus);

		% receive a request for connection from another drone
		{connection, NeighbourDroneAddr} ->
			NeighbourDroneAddr ! confirmConnection,
			drone_Loop(Manager_Server_Addr, DroneID, NeighbourList ++ [NeighbourDroneAddr], SupportedWeight, DronePosition, DroneBattery, RechargingStations, DroneStatus);

		% receive a drone status query from manager
		{droneStatus, Manager_Server_Addr} ->
			Manager_Server_Addr ! {droneStatus, self(), DroneID, DroneStatus},
			drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, DronePosition, DroneBattery, RechargingStations, DroneStatus) ;

		% check that all the neighbours are alive, remove dead, if <= 2 ask more to manager
		{electionFailed} ->
			NewNeighbourList = checkNeighbour(NeighbourList, [], DroneID, self(), Manager_Server_Addr),
			drone_Loop(Manager_Server_Addr, DroneID, NewNeighbourList, SupportedWeight, DronePosition, DroneBattery, RechargingStations, DroneStatus);
		
		{ makeOrder, PidClient, ClientID, OrderID, Description }= Msg->
			io:format("~n about to start election: ~n"),
			InitElection = spawn(drone, initElection, [self(), DroneID, NeighbourList]),
			InitElection! Msg,
			drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, DronePosition, DroneBattery, RechargingStations, DroneStatus);
		
		{excessiveWeight, ClientID, OrderID}->
			io:format("~n the package weighs too much: ~n"),
			drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, DronePosition, DroneBattery, RechargingStations, DroneStatus);
		
		{elected, ClientID, OrderID, Source, Destination }->
			{D1,D2}= Destination, 
			{S1,S2}= Source,
			Wait=(math:sqrt( math:pow( D1-S1, 2 ) + math:pow( D2-S2, 2 ))),
			drone_Loop_Busy(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, DronePosition, DroneBattery, RechargingStations, delivering, Wait, Destination);
		
		{lowBattery}->	
			RecStation=election:findNearestRechargingStation(DronePosition, RechargingStations),
			{D1,D2}= RecStation, 
			{S1,S2}= DronePosition,
			Wait=(math:sqrt( math:pow( D1-S1, 2 ) + math:pow( D2-S2, 2 )) + 100 ), % 100 standard time the drone spends at the recharging station to fully recharge
			drone_Loop_Busy(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, DronePosition, DroneBattery, RechargingStations, recharging, Wait, RecStation)
	end
.

drone_Loop_Busy(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, DronePosition, DroneBattery, RechargingStations, DroneStatus, Wait, Dest)->
	receive
		{droneStatus, Manager_Server_Addr} ->
			Manager_Server_Addr ! {droneStatus, self(), DroneID, DroneStatus},
			drone_Loop_Busy(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, DronePosition, DroneBattery, RechargingStations, DroneStatus,Wait, Dest) 
	end,
	timer:sleep(Wait),
	case DroneStatus of
		delivering -> drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, Dest, DroneBattery-round((Wait/10)), RechargingStations, idle);
		recharging -> drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight, Dest, 100, RechargingStations, idle)
	end
.
% take a list of drones to connect to, in case of failure ask for new drone addresses to the manager
% return the list of online and connected drones
connect_to_drones(DronesList, DronesAlreadyConnectedTo, MyDroneID, MyDroneAddr, ManagerAddr)->
    case DronesList of
        []     ->   DronesAlreadyConnectedTo ;
        [X|Xs] ->   X ! {connection, MyDroneAddr},

                    % receive confirmation from the other drone
                    receive confirmConnection -> NewDrone = X
                    after % in case of timeout consider the drone dead and send a request to the manager for a single new drone
				    2000 -> NewDrone = requestNewDrone(DronesList, DronesAlreadyConnectedTo, MyDroneID, MyDroneAddr, ManagerAddr, 3)
                    % requestNewDrone() ask the manager, after the reply,
                    % checks that the drone it's not connected to the new candidate drone or is already in the candidates.
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
.




%% ====================================================================
%% Internal functions
%% ====================================================================

requestNewDrone(DronesList, DronesAlreadyConnectedTo, MyDroneID, MyDroneAddr, ManagerAddr, Counter)->
	if
	    Counter > 0 ->
	        ManagerAddr ! {requestDroneAddr, MyDroneID, MyDroneAddr},
		    receive
			    {newDrone, _NewDroneID, NewDroneAddr} ->
			        case lists:member( NewDroneAddr, DronesList ++ DronesAlreadyConnectedTo) of
			        true -> requestNewDrone(DronesList, DronesAlreadyConnectedTo, MyDroneID, MyDroneAddr, ManagerAddr, Counter-1);
			        false -> NewDroneAddr
			        end
			after 2000 -> {}
		    end ;
		% in case of "Counter" failed attempt
		Counter == 0 -> {}
	end
.


% take a list of Neighbour drones, in case of failure or timeout remove them, if the list becomes <=2 ask for new drones addresses to the manager
% return the list of online and connected Neighbour drones

% check that all the neighbours are alive, remove dead, if <= 2 ask more to manager
checkNeighbour(NeighbourList, OnlineDrones, MyDroneID, MyDroneAddr, ManagerAddr)->
    case NeighbourList of

        [X|Xs] ->   X ! {confirmConnection, self(), MyDroneAddr},

                    receive confirmConnection ->
					    checkNeighbour(Xs, OnlineDrones ++ [X], MyDroneID, MyDroneAddr, ManagerAddr)
                    after % in case of timeout consider the drone dead, don't add it to online list
				    2000 -> checkNeighbour(Xs, OnlineDrones, MyDroneID, MyDroneAddr, ManagerAddr)
                    end;
	   []     ->
		   		Len = length(OnlineDrones),
				if
				    Len < 3 -> NewDrone= requestNewDrone(NeighbourList, OnlineDrones, MyDroneID, MyDroneAddr, ManagerAddr, 0),
					           checkNeighbour(NeighbourList, OnlineDrones ++ [NewDrone], MyDroneID, MyDroneAddr, ManagerAddr) ;
					true -> true
				end
	end
.
