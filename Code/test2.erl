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


																							
	Drone1 = spawn(drone, start, [PrimaryManagerAddr, 1, 60, {rand:uniform(100),rand:uniform(100)}, []]), % 1 is ID, 60 is supported weight
	PrimaryManagerAddr ! { joinRequest, 1, Drone1 },
    io:format("Drone1: ~w~n", [Drone1]),
    timer:sleep(200),

	Drone2 = spawn(drone, start, [PrimaryManagerAddr, 2, 60, {rand:uniform(100),rand:uniform(100)}, []]), % 2 is ID, 60 is supported weight
	PrimaryManagerAddr ! { joinRequest, 2, Drone2 },
    io:format("Drone2: ~w~n", [Drone2]),
    timer:sleep(200),

    Drone3 = spawn(drone, start, [PrimaryManagerAddr, 3, 60, {rand:uniform(100),rand:uniform(100)}, []]), % 3 is ID, 60 is supported weight
	PrimaryManagerAddr ! { joinRequest, 3, Drone3 },
    io:format("Drone3: ~w~n", [Drone3]),

    timer:sleep(4000),
    ok
.




	%start(Manager_Server_Addr, DroneID, SupportedWeight, DronePosition, RechargingStations)
%	Drone1= spawn(drone, start, [PrimaryManagerAddr, 1, 60, {50, 60}, [{40, 50}]]), % 1 is the id 60 is the max carry weight
%	Drone2= spawn(drone, start, [PrimaryManagerAddr, 2, 50, {60, 60}, [{40, 50}]]),
%	Drone3= spawn(drone, start, [PrimaryManagerAddr, 3, 90, {50, 64}, [{40, 50}]]),



% other test made
% - with no drones, ask one from the shell
% - with no drones, ask joinRequest from the shell

