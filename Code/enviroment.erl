%% @author Andrea
%% @doc @todo Add description to 'Enviroment'.


-module('enviroment').

%% ====================================================================
%% API functions
%% ====================================================================
-export([spawn_loop/0]).

%enviroment:spawn_loop().

%spawns a client with random X and Y coordinates(in 1-100 range), does it continuously after a random ammount of time
spawn_loop()->
	spawn(client, delivery_Request, ["",round(rand:uniform(100)), round(rand:uniform(100))]),
	timer:sleep(round(timer:seconds(rand:uniform(10)))),
	spawn_loop().
	


%% ====================================================================
%% Internal functions
%% ====================================================================


