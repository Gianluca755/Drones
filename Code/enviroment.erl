%% @author Andrea
%% @doc @todo Add description to 'Enviroment'.


-module('enviroment').

%% ====================================================================
%% API functions
%% ====================================================================
-export([spawn_loop/0]).

spawn_loop()->
	a=rand:uniform(),
	if
		%%
		(a > 0.9) ->
			spawn(client, delivery_Request, [server, round(rand:uniform(100)), round(rand:uniform(100)), round(rand:uniform(1000))]) 
	end,
spawn_loop().
	
	

%% ====================================================================
%% Internal functions
%% ====================================================================


