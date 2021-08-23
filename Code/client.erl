%% @author Andrea
%% @doc @todo Add description to 'Client'.

-module('client').
-export([start/3]).

-export([loopClient/4]).


start(ClientID, BrokerAddr, BckBrokerAddr) ->
    Pid = spawn(client, loopClient, [ClientID, BrokerAddr, BckBrokerAddr, 0]),
    io:format("pid client: ~w~n", [Pid])
.


loopClient(ClientID, BrokerAddr, BckBrokerAddr, CounterOrder) ->
    % receive instruction from developer
    receive
    makeOrder ->    Msg = {makeOrder, self(), ClientID,
                            CounterOrder, % this is the OrderID
                            {
                            {rand:uniform(100), rand:uniform(100) }, % source
                            {rand:uniform(100), rand:uniform(100) }, % destination
                            rand:uniform(80) % weight
                            }},
                    BrokerAddr ! Msg,
                    receive confirmedOrder -> io:format("Order received ~n")
                    end,

                    loopClient(ClientID, BrokerAddr, BckBrokerAddr, CounterOrder+1)
                    ;

    {statusOrder, OrderID} ->   BrokerAddr ! { queryOrder, self(), ClientID, OrderID },
                                receive
                                    orderNotPresent -> io:format("Order not present in broker ~n") ;
                                    Status -> io:format("The status of the order is: ~w~n", [Status])
                                end
    end,

    loopClient(ClientID, BrokerAddr, BckBrokerAddr, CounterOrder)
.






