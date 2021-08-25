%% @author Andrea
%% @doc @todo Add description to drone.


-module(drone).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start/3]).
-export([connect_to_drones/5, requestNewDrone/6, checkNeighbour/5, drone_Loop/4]).


start(Manager_Server_Addr, DroneID, SupportedWeight) ->

    DroneAddr = spawn(drone, drone_Loop, [Manager_Server_Addr, DroneID, [], SupportedWeight]),
    Manager_Server_Addr ! { joinRequest, DroneID, DroneAddr }
.


drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight) -> % NeighbourList is only addresses
	receive

		% receive the drone list to connect to, form manager
		{droneList, DronesList} ->
			 NewNeighbourList = connect_to_drones(DronesList, [], DroneID, self(), Manager_Server_Addr),
			 case NewNeighbourList of
			 []     -> timer:sleep(1000), Manager_Server_Addr ! { joinRequest, DroneID, self() } ;
			 _Other -> skip
			 end,
			 io:format("Drone ~w, ID ~w, List : ~w~n", [DroneID, self(), NewNeighbourList]),
			 drone_Loop(Manager_Server_Addr, DroneID, NewNeighbourList, SupportedWeight);

		% receive a request for connection from another drone
		{connection, NeighbourDroneAddr} ->
			NeighbourDroneAddr ! confirmConnection,
			% avoid inserting duplicates
			Condition = lists:member(NeighbourDroneAddr, NeighbourList),
			if
			Condition == false ->
			    io:format("Drone ~w, ID ~w, List : ~w~n", [DroneID, self(), NeighbourList ++ [NeighbourDroneAddr]),
			    drone_Loop(Manager_Server_Addr, DroneID, NeighbourList ++ [NeighbourDroneAddr], SupportedWeight ) ;

			Condition == true -> drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight )
			end;

		% receive a drone status query from manager
		{droneStatus, Manager_Server_Addr} ->
			Manager_Server_Addr ! {droneStatus, self(), DroneID},
			drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight) ;

		% check that all the neighbours are alive, remove dead, if <= 2 ask more to manager
		{electionFailed} ->
			NewNeighbourList = checkNeighbour(NeighbourList, [], DroneID, self(), Manager_Server_Addr),
			drone_Loop(Manager_Server_Addr, DroneID, NewNeighbourList, SupportedWeight);

		{ makeOrder, _PidClient, ClientID, OrderID, Description } = Msg->
			io:format("~n about to start election: ~n"),
			InitElection = spawn(drone, initElection, [self(), NeighbourList]),
			InitElection! Msg,
			drone_Loop(Manager_Server_Addr, DroneID, NeighbourList, SupportedWeight)
	end
.

%% ====================================================================
%% Internal functions
%% ====================================================================


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


% take a list of Neighbour drones, in case of failure or timeout remove them, if the list becomes <=2 ask for new drones addresses to the manager
% return the list of online and connected Neighbour drones

% check that all the neighbours are alive, remove dead, if < 2 ask more to manager
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
				    Len < 2 -> NewDrone= requestNewDrone(NeighbourList, OnlineDrones, MyDroneID, MyDroneAddr, ManagerAddr, 0),
					           checkNeighbour(NeighbourList, OnlineDrones ++ [NewDrone], MyDroneID, MyDroneAddr, ManagerAddr) ;
					true -> true
				end
	end
.
