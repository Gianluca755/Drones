%% @author Andrea
%% @doc @todo Add description to 'Client'.


-module('client').


-export([delivery_Request/3, status_Request/2]).
%sends a delivery requests, randomizes the X and Y coordinates of the delivery location(in 1-100 range) and the weight of the package(in 1-1000 range)
delivery_Request(Broker_Server_Addr, PosA_X, PosA_Y) ->
	Broker_Server_Addr ! {self(), {PosA_X, PosA_Y, round(rand:uniform(100)), round(rand:uniform(100)), round(rand:uniform(1000))}}.


status_Request(Broker_Server_Addr, Id_Req)->
	Broker_Server_Addr ! {self(), Id_Req}, 
	receive
		{Broker_Server_Addr, Status}->
			   Status
	end.

