%% @author Andrea
%% @doc @todo Add description to drone.


-module(drone).

%% ====================================================================
%% API functions
%% ====================================================================
-export([drone_Loop_init/3]).


drone_Loop_init(Manager_Server_Addr, DroneID, NeighbourList)->
	join_Request(Manager_Server_Addr, DroneID),
	drone_Loop(Manager_Server_Addr, DroneID, NeighbourList)
.

drone_Loop(Manager_Server_Addr, DroneID, NeighbourList) ->

	receive
		{confirmConnection, DroneAddr} ->
			DroneAddr ! {confirmConnection};
		%receive the drone list to connect to form manager
		{dronesList, Manager_Server_Addr, DronesList} ->
			 NeighbourList= connect_to_drones(DronesList,[], DroneID, self(), Manager_Server_Addr);
		%receive a request for connection from another drone
		{connection, DroneAddr, NeighbourDroneID, NeighbourDroneAddr} ->
			DroneAddr ! {confirmConnection, self(), DroneID},
			drone_Loop(Manager_Server_Addr, DroneID, NeighbourList ++ [{NeighbourDroneID, NeighbourDroneAddr}]);
		%receive a drone status query from manager
		{droneStatus, Manager_Server_Addr} ->
			Manager_Server_Addr ! {droneStatus, self(), DroneID};
		% check that all the neighbours are alive, remove dead, if <= 2 ask more to manager
		{electionFailed} ->  
			NeighbourList= checkNeighbour(NeighbourList, [], DroneID, self(), Manager_Server_Addr)
	end,
	drone_Loop(Manager_Server_Addr, DroneID, NeighbourList)
.

%as a new drone send a join request to the manager
join_Request(Manager_Server_Addr, DroneID) ->
	Manager_Server_Addr ! {joinRequest, self(), DroneID, {}, {rand:uniform(1500)}}
.

	%Manager_Server_Addr ! {inDelivery, self(), ClientID, OrderID, {}},
	%Manager_Server_Addr ! {delivered, {}, ClientID, OrderID, {}}


	%Drone_Addr ! {election, self(), ClientID, OrderID, {Source, Destination, Weight}}


% take a list of drones to connect to, in case of failure ask for new drone addresses to the manager
% return the list of online and connected drones
connect_to_drones(DronesList, DronesAlreadyConnectedTo, MyDroneID, MyDroneAddr, ManagerAddr)->
    case DronesList of
        []     -> [] ;
        [X|Xs] -> X ! {confirmConnection, self()},
                  receive % receive confirmation from the other drone
						{confirmConnection, DroneAddr, DroneID} -> 
							NewDrone={DroneID, DroneAddr}
                  after % in case of timeout consider the drone dead and send a request to the manager for a single new drone
					10 -> NewDrone= requestNewDrone(DronesList, DronesAlreadyConnectedTo, MyDroneID, MyDroneAddr, ManagerAddr, 0)
								
                  % after the request to the server, need to check that the drone is not trying to connect to itself
                  % nor that it's already connected to that drone.

                  % after 3 fail attempt of obtaining a new drone leave it
                  end,
				  if
					  NewDrone == {}->
						   connect_to_drones(Xs, DronesAlreadyConnectedTo, MyDroneID, MyDroneAddr, ManagerAddr)
				  end,	  
                  [ NewDrone ] ++ connect_to_drones(Xs, DronesAlreadyConnectedTo ++ [NewDrone], MyDroneID, MyDroneAddr, ManagerAddr)
    end
.


failure(Manager_Server_Addr, DroneID)->
	Manager_Server_Addr ! {failureNotification, self(), DroneID}
.

%% ====================================================================
%% Internal functions
%% ====================================================================

requestNewDrone(DronesList, DronesAlreadyConnectedTo, MyDroneID, MyDroneAddr, ManagerAddr, Counter)->
	if counter < 3 ->
		ManagerAddr ! {requestDroneAddr, self(), MyDroneID},
		receive 
			{newDrone, ManagerAddr, NewDrone}->
				AlreadyConnectedTo= ets:member(DronesAlreadyConnectedTo, element(1,NewDrone)),
				if
					AlreadyConnectedTo or element(1,NewDrone) == MyDroneID ->
						requestNewDrone(DronesList, DronesAlreadyConnectedTo, MyDroneID, MyDroneAddr, ManagerAddr, Counter + 1)
				end,
				ReturnedDrone=NewDrone
		end
	end,
	ReturnedDrone={}
.
% take a list of Neighbour drones, in case of failure or timeout remove them, if the list becomes <=2 ask for new drones addresses to the manager
% return the list of online and connected Neighbour drones

% check that all the neighbours are alive, remove dead, if <= 2 ask more to manager
checkNeighbour(NeighbourList, ConfirmedDronesConnectedTo, MyDroneID, MyDroneAddr, ManagerAddr)->
    case NeighbourList of
        
        [X|Xs] -> X ! {confirmConnection, self(), MyDroneAddr},
                  receive % receive confirmation from the other drone
						{confirmConnection} -> 
							checkNeighbour(Xs, ConfirmedDronesConnectedTo ++ [X], MyDroneID, MyDroneAddr, ManagerAddr)
                  after % in case of timeout consider the drone dead, don't add it to confirmed list
					10 -> checkNeighbour(Xs, ConfirmedDronesConnectedTo, MyDroneID, MyDroneAddr, ManagerAddr)
								
                  % after the request to the server, need to check that the drone is not trying to connect to itself
                  % nor that it's already connected to that drone.

                  % after 3 fail attempt of obtaining a new drone leave it
                  end;
	   []     -> 
		   		Len=length(ConfirmedDronesConnectedTo),
				if Len < 3 ->
					  NewDrone= requestNewDrone(NeighbourList, ConfirmedDronesConnectedTo, MyDroneID, MyDroneAddr, ManagerAddr, 0),
					  checkNeighbour(NeighbourList, ConfirmedDronesConnectedTo ++ [NewDrone], MyDroneID, MyDroneAddr, ManagerAddr)
				end
	end
.