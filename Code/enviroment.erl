%% @author Andrea
%% @doc @todo Add description to 'Enviroment'.


-module('enviroment').

%% ====================================================================
%% API functions
%% ====================================================================
-export([spawn_loop/0, prova/1]).

%enviroment:spawn_loop().
spawn_loop()->
	
	io:format("~w", ["a"]),
	spawn(client, delivery_Request, ["a",round(rand:uniform(100)), round(rand:uniform(100)), round(rand:uniform(1000))]) ,
	%spawn(enviroment, prova,["aaaaaaa"]),
	io:format("~w", ["c"]),
	timer:sleep(round(timer:seconds(rand:uniform(10)))),
	spawn_loop().
	
prova(A)->
	io:format("~w", [A]).

%% ====================================================================
%% Internal functions
%% ====================================================================


