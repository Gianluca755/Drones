%% @author Andrea
%% @doc @todo Add description to drone.


-module(drone).

%% ====================================================================
%% API functions
%% ====================================================================
-export([join_Request/2]).
drone_Loop_init(Manager_Server_Addr, DroneID, NeighbourList)->
	join_Request(Manager_Server_Addr,DroneID),
drone_Loop(Manager_Server_Addr, DroneID, NeighbourList)
.

drone_Loop(Manager_Server_Addr, DroneID, NeighbourList)->
	
	
	receive
		{dronesList, Manager_Server_Addr, DronesList}->
			connect_to_drones(DronesList),
		{ackJoin, DroneAddr, NeighbourDroneID}->
			drone_Loop(Manager_Server_Addr, DroneID, NeighbourList ++ NeighbourDroneID),
		{droneStatus, Manager_Server_Addr}->
			Manager_Server_Addr ! {droneStatus, self(), DroneID}
	end
	
	drone_Loop(Manager_Server_Addr, DroneID, NeighbourTable)
	.

join_Request(Manager_Server_Addr, DroneID) ->
	Manager_Server_Addr ! {joinRequest, self(), DroneID, {rand:uniform(1500)},{}}
.



	Manager_Server_Addr ! {inDelivery, self(), ClientID, OrderID, {}},
	Manager_Server_Addr ! {delivered, {}, ClientID, OrderID, {}}


	Drone_Addr ! {election, self(), ClientID, OrderID, {Source, Destination, Weight}}



connect_to_drones(DronesList)->
	
	if
		length(DronesList) >0 ->
			hd(DronesList) ! {connection, self(), DroneID},
			connect_to_drones(tl(DronesList))
	end
.

failure(Manager_Server_Addr, DroneID)->
	Manager_Server_Addr ! {failureNotification, self(), DroneID}
.

%% ====================================================================
%% Internal functions
%% ====================================================================


