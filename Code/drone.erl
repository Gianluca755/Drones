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
		{dronesList, Manager_Server_Addr, DronesList} ->
			connect_to_drones(DronesList, DroneID);

		{connection, DroneAddr, NeighbourDroneID} ->
			drone_Loop(Manager_Server_Addr, DroneID, NeighbourList ++ {DroneAddr, NeighbourDroneID});

		{droneStatus, Manager_Server_Addr} ->
			Manager_Server_Addr ! {droneStatus, self(), DroneID}

		% electionFailed ->  % check that all the neighbours are alive, remove dead, if <= 2 ask more to manager
	end,
	drone_Loop(Manager_Server_Addr, DroneID, NeighbourList)
.

join_Request(Manager_Server_Addr, DroneID) ->
	Manager_Server_Addr ! {joinRequest, self(), DroneID, {}, {rand:uniform(1500)}}
.

	%Manager_Server_Addr ! {inDelivery, self(), ClientID, OrderID, {}},
	%Manager_Server_Addr ! {delivered, {}, ClientID, OrderID, {}}


	%Drone_Addr ! {election, self(), ClientID, OrderID, {Source, Destination, Weight}}


% take a list of drones to connect to, in case of failure ask for new drone addresses to the manager
% return the list of online and connected drones
connect_to_drones(DronesList, MyDroneID, MyDroneAddr, ManagerAddr)->
    case DronesList of
        []     -> [] ;
        [X|Xs] -> X ! {connection, self(), MyDroneID, MyDroneAddr},
                  receive % receive confirmation from the other drone

                  after % in case of timeout consider the drone dead and send a request to the manager for a single new drone

                  % after the request to the server, need to check that the drone is not trying to connect to itself.
                  end,
                  [ {NewDroneID, NewDroneAddr} ] ++
                  connect_to_drones(Xs,  MyDroneID, MyDroneAddr, ManagerAddr)
    end
.


failure(Manager_Server_Addr, DroneID)->
	Manager_Server_Addr ! {failureNotification, self(), DroneID}
.

%% ====================================================================
%% Internal functions
%% ====================================================================


