%% @author Andrea
%% @doc @todo Add description to 'Client'.


-module('client').


-export([delivery_Request/4, status_Request/2]).

delivery_Request(server, posA_X, posA_Y, weight) ->
	server ! {self(), {posA_X, posA_Y, round(rand:uniform(100)), round(rand:uniform(100)), weight}}.

status_Request(server, id_Req)->
	server ! {self(), id_Req}, 
	receive
		{server, status}->
			   status
	end.