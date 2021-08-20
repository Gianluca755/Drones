%% @author Andrea
%% @doc @todo Add description to 'Enviroment'.


-module('environment').

%% ====================================================================
%% API functions
%% ====================================================================
-export([spawn_loop_start/0, spawn_loop/2, spawn_drones/3, spawn_drone/2]).


%enviroment:spawn_loop_start().

spawn_loop_start()->
	spawn_loop(0, "Broker_Server_Addr").

%spawns a client with random X and Y coordinates(in 1-100 range), does it continuously after a random ammount of time
spawn_loop(ClientID, Broker_Server_Addr)->
	spawn(client, delivery_Request, [ClientID, 0, Broker_Server_Addr, rand:uniform(100), rand:uniform(100)]),
	timer:sleep(round(timer:seconds(rand:uniform(10)))),
	spawn_loop(ClientID, Broker_Server_Addr).
	
spawn_drones(DroneID, NumberOfDrones, Manager_Serevr_Addr)->
	if NumberOfDrones > 0 ->
		spawn(drone, join_Request, [Manager_Serevr_Addr, DroneID])
	end,
	spawn_drones(DroneID + 1, NumberOfDrones - 1, Manager_Serevr_Addr)
.

spawn_drone(DroneID, Manager_Serevr_Addr)->	
		spawn(drone, drone_Loop, [Manager_Serevr_Addr, DroneID])	
.
%% ====================================================================
%% Internal functions
%% ====================================================================


