%% @author Andrea
%% @doc @todo Add description to 'Client'.


-module('client').


-export([delivery_Request/4, status_Request/2]).

delivery_Request(Server, PosA_X, PosA_Y, Weight) ->
	io:format("~w", ["prova"]).
	%Server ! {self(), {PosA_X, PosA_Y, round(rand:uniform(100)), round(rand:uniform(100)), Weight}}.

status_Request(Server, Id_Req)->
	Server ! {self(), Id_Req}, 
	receive
		{Server, Status}->
			   Status
	end.

