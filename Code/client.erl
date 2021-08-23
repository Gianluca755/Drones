%% @author Andrea
%% @doc @todo Add description to 'Client'.

-module('client').
-export([start]).
-export([delivery_Request/5, status_Request/3]).

start(ClientID, brokerAddr, brokerAddrBck) ->
    loopClient(ClientID, brokerAddr, brokerAddrBck)
.

loopClient(ClientID, brokerAddr, brokerAddrBck) ->
    % receive instruction from developer
    receive
    makeOrder ->    Msg = {makeOrder, self(), ClientID, OrderID, {
                        {rand:uniform(100), rand:uniform(100) }, % source
                        {rand:uniform(100), rand:uniform(100) }, % destination
                        rand:uniform(80) % weight
                        }},
                    brokerAddr ! Msg,
                    receive confirmedOrder -> io:format("Order received ~n")
                    end
                    ;
    {statusOrder, OrderID} ->   brokerAddr ! { queryOrder, self(), ClientID, OrderID },
                                receive
                                    orderNotPresent -> io:format("Order not present in broker ~n") ;
                                    Status -> io:format("The status of the order is: ~w~n", [Status])
                                end
    end,

    loopClient(ID, brokerAddr, brokerAddrBck)
.






