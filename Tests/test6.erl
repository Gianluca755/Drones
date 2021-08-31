% c(manager,[debug_info]). c(broker,[debug_info]). c(client,[debug_info]). c(utils). c(drone,[debug_info]). c(election, [debug_info]). c(test6,[debug_info]). c("../Tests/test6", [debug_info]).

-module(test6).
-export([startOrder/0]).

startOrder() ->
    PrimaryManagerAddr = spawn(manager, startPrimary, []),
    BckManagerAddr = spawn(manager, startBck, [PrimaryManagerAddr]),

    io:format("~nPrimary manager: ~w~n", [PrimaryManagerAddr]),
    io:format("Backup manager: ~w~n", [BckManagerAddr]),

    PrimaryBrokerAddr = spawn(broker, startPrimary, [PrimaryManagerAddr, BckManagerAddr]),
    BckBrokerAddr = spawn(broker, startBck, [PrimaryBrokerAddr, PrimaryManagerAddr, BckManagerAddr]),

    timer:sleep(200),


    PidClient = spawn(client, loopClient, [55, PrimaryBrokerAddr, BckBrokerAddr, 0]), % 55 is a random ID, 0 is the counter for orders
    io:format("PidClient: ~w~n", [PidClient]),


	spawn(drone, start, [PrimaryManagerAddr, 1, 60, {rand:uniform(100),rand:uniform(100)}, [{1,1}]]), % 1 is ID, 60 is supported weight
	spawn(drone, start, [PrimaryManagerAddr, 2, 60, {rand:uniform(100),rand:uniform(100)}, [{1,1}]]), % 2 is ID, 60 is supported weight
    spawn(drone, start, [PrimaryManagerAddr, 3, 60, {rand:uniform(100),rand:uniform(100)}, [{1,1}]]), % 3 is ID, 60 is supported weight
	spawn(drone, start, [PrimaryManagerAddr, 4, 60, {rand:uniform(100),rand:uniform(100)}, [{1,1}]]), % 2 is ID, 60 is supported weight
	spawn(drone, start, [PrimaryManagerAddr, 5, 60, {rand:uniform(100),rand:uniform(100)}, [{1,1}]]), % 2 is ID, 60 is supported weight
	spawn(drone, start, [PrimaryManagerAddr, 6, 60, {rand:uniform(100),rand:uniform(100)}, [{1,1}]]), % 2 is ID, 60 is supported weight
	
    io:format("Drone syncronization ~n"),
    timer:sleep(5000),

    PidClient ! makeOrder,
    timer:sleep(20000),
	ok
.





