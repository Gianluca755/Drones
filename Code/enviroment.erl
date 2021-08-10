%% @author Andrea
%% @doc @todo Add description to 'Enviroment'.


-module('enviroment').

%% ====================================================================
%% API functions
%% ====================================================================
-export([spawn_loop_start/0, spawn_loop/2]).


%enviroment:spawn_loop_start().

spawn_loop_start()->
	spawn_loop(0, "Broker_Server_Addr").

%spawns a client with random X and Y coordinates(in 1-100 range), does it continuously after a random ammount of time
spawn_loop(ClientID, Broker_Server_Addr)->
	spawn(client, delivery_Request, [ClientID, 0, Broker_Server_Addr, round(rand:uniform(100)), round(rand:uniform(100))]),
	timer:sleep(round(timer:seconds(rand:uniform(10)))),
	spawn_loop(ClientID, Broker_Server_Addr).
	


%% ====================================================================
%% Internal functions
%% ====================================================================


