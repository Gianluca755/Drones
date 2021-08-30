% c(manager,[debug_info]). c(broker,[debug_info]). c(client,[debug_info]). c(utils). c(drone,[debug_info]). c(election). c(test6,[debug_info]).

-module(test6).

-compile(export_all).

startOrder() ->
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


	Drone1 = spawn(drone, start, [PrimaryManagerAddr, 1, 60, {rand:uniform(100),rand:uniform(100)}, [{1,1}]]), % 1 is ID, 60 is supported weight
	PrimaryManagerAddr ! { joinRequest, 1, Drone1 },
    timer:sleep(200),

	Drone2 = spawn(drone, start, [PrimaryManagerAddr, 2, 60, {rand:uniform(100),rand:uniform(100)}, [{1,1}]]), % 2 is ID, 60 is supported weight
	PrimaryManagerAddr ! { joinRequest, 2, Drone2 },
    timer:sleep(200),

    Drone3 = spawn(drone, start, [PrimaryManagerAddr, 3, 60, {rand:uniform(100),rand:uniform(100)}, [{1,1}]]), % 3 is ID, 60 is supported weight
	PrimaryManagerAddr ! { joinRequest, 3, Drone3 },


    io:format("Drone syncronization ~n"),
    timer:sleep(5000),
    PidClient ! makeOrder,
    timer:sleep(20000)

.


