-module(test2).
-compile(export_all).

% c(manager). c(broker). c(client). c(utils). c(drone). c(test2).

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

	%start(Manager_Server_Addr, DroneID, SupportedWeight, DronePosition, RechargingStations)
	Drone1= spawn(drone, start, [PrimaryManagerAddr, 1, 60, {50, 60}, [{40, 50}]]), %1 is the id 60 is the max carry weight
	Drone2= spawn(drone, start, [PrimaryManagerAddr, 2, 50, {60, 60}, [{40, 50}]]),
	Drone3= spawn(drone, start, [PrimaryManagerAddr, 3, 90, {50, 64}, [{40, 50}]]),


    PidClient ! makeOrder,
    timer:sleep(2000),
    PidClient ! {statusOrder, 0}, % orderID = 0 for first order
    ok
.
