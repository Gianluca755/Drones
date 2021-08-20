%% @author Andrea
%% @doc @todo Add description to 'Client'.


-module('client').


-export([delivery_Request/5, status_Request/3]).

%sends a delivery requests, randomizes the X and Y coordinates of the delivery location(in 1-100 range) and the weight of the package(in 1-1000 range)
delivery_Request(ClientID, OrderID, Broker_Server_Addr, PosA_X, PosA_Y) ->
	Broker_Server_Addr ! {delivery_Request, self(), ClientID, OrderID,  {{PosA_X, PosA_Y}, {rand:uniform(100), rand:uniform(100)}, rand:uniform(1000)}}.


status_Request(Broker_Server_Addr, ClientID, OrderID)->
	Broker_Server_Addr ! {queryOrder, self(), ClientID, OrderID}, 
	receive
		{_, _, _, Status}->
			   io:format("The status of the order is: ~w~n",[Status]);
		orderNotPresent -> 
				io:format("The order is not persent ~n")
	end.

