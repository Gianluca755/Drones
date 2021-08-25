-module(test2).
-compile(export_all).

% c(manager,[debug_info]). c(broker,[debug_info]). c(client,[debug_info]). c(utils). c(drone,[debug_info]).

% 3 drones join the network
startDrones() ->
    PrimaryManagerAddr = spawn(manager, startPrimary, []),
    BckManagerAddr = spawn(manager, startBck, [PrimaryManagerAddr]),

    io:format("~nPrimary manager: ~w~n", [PrimaryManagerAddr]),
    io:format("Backup manager: ~w~n", [BckManagerAddr]),

    PrimaryBrokerAddr = spawn(broker, startPrimary, [PrimaryManagerAddr, BckManagerAddr]),
    BckBrokerAddr = spawn(broker, startBck, [PrimaryBrokerAddr, PrimaryManagerAddr, BckManagerAddr]),

    timer:sleep(200),
    io:format("~n~n"),


	Drone1 = spawn(drone, drone_Loop, [PrimaryManagerAddr, 1, [], 60]), % 1 is ID, 60 is supported weight
	PrimaryManagerAddr ! { joinRequest, 1, Drone1 },
    io:format("Drone1: ~w~n", [Drone1]),
    timer:sleep(200),

	Drone2 = spawn(drone, drone_Loop, [PrimaryManagerAddr, 2, [], 60]), % 2 is ID, 60 is supported weight
	PrimaryManagerAddr ! { joinRequest, 2, Drone2 },
    io:format("Drone2: ~w~n", [Drone2]),
    timer:sleep(200),

    Drone3 = spawn(drone, drone_Loop, [PrimaryManagerAddr, 3, [], 60]), % 3 is ID, 60 is supported weight
	PrimaryManagerAddr ! { joinRequest, 3, Drone3 },
    io:format("Drone3: ~w~n", [Drone3]),


    timer:sleep(4000),
    ok
.


% other test made

% - with no drones, ask one from the shell
% - with no drones, ask joinRequest from the shell


