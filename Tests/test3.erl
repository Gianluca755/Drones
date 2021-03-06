-module(test3).
-compile(export_all).

% c(manager,[debug_info]). c(broker,[debug_info]). c(client,[debug_info]). c(utils). c(drone,[debug_info]). c(election). c("../Tests/test3", [debug_info]).

% make order but no drones
startNoDrones() ->
    PrimaryManagerAddr = spawn(manager, startPrimary, []),
    BckManagerAddr = spawn(manager, startBck, [PrimaryManagerAddr]),

    io:format("~nPrimary manager: ~w~n", [PrimaryManagerAddr]),
    io:format("Backup manager: ~w~n", [BckManagerAddr]),

    PrimaryBrokerAddr = spawn(broker, startPrimary, [PrimaryManagerAddr, BckManagerAddr]),
    BckBrokerAddr = spawn(broker, startBck, [PrimaryBrokerAddr, PrimaryManagerAddr, BckManagerAddr]),

    timer:sleep(200),
    io:format("~n~n"),

    PidClient = spawn(client, loopClient, [55, PrimaryBrokerAddr, BckBrokerAddr, 0]), % 55 is a random ID, 0 is the counter for orders
    io:format("PidClient: ~w~n", [PidClient]),



    PidClient ! makeOrder,
    timer:sleep(2000),
    PidClient ! {statusOrder, 0}, % orderID = 0 for first order
    ok
.

% make order with some drones
startDrones() ->
    PrimaryManagerAddr = spawn(manager, startPrimary, []),
    BckManagerAddr = spawn(manager, startBck, [PrimaryManagerAddr]),

    io:format("~nPrimary manager: ~w~n", [PrimaryManagerAddr]),
    io:format("Backup manager: ~w~n", [BckManagerAddr]),

    PrimaryBrokerAddr = spawn(broker, startPrimary, [PrimaryManagerAddr, BckManagerAddr]),
    BckBrokerAddr = spawn(broker, startBck, [PrimaryBrokerAddr, PrimaryManagerAddr, BckManagerAddr]),

    timer:sleep(200),
    io:format("~n~n"),

    PidClient = spawn(client, loopClient, [55, PrimaryBrokerAddr, BckBrokerAddr, 0]), % 55 is a random ID, 0 is the counter for orders
    io:format("PidClient: ~w~n", [PidClient]),

	_Drone1= spawn(drone, start, [PrimaryManagerAddr, 1, 60, {rand:uniform(100),rand:uniform(100)}, []]), timer:sleep(200),
	_Drone2= spawn(drone, start, [PrimaryManagerAddr, 2, 60, {rand:uniform(100),rand:uniform(100)}, []]), timer:sleep(200),
	_Drone3= spawn(drone, start, [PrimaryManagerAddr, 3, 60, {rand:uniform(100),rand:uniform(100)}, []]), timer:sleep(200),


    PidClient ! makeOrder,
    timer:sleep(2000),
    PidClient ! {statusOrder, 0}, % orderID = 0 for first order
    ok
.
