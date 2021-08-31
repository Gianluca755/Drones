-module(test2).
-compile(export_all).


% c(manager,[debug_info]). c(broker,[debug_info]). c(client,[debug_info]). c(utils). c(drone,[debug_info]). c("../Tests/test2", [debug_info]).


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


    spawn(drone, start, [PrimaryManagerAddr, 1, 60, {rand:uniform(100),rand:uniform(100)}, []]), % 1 is ID, 60 is supported weight
    timer:sleep(200),

	spawn(drone, start, [PrimaryManagerAddr, 2, 60, {rand:uniform(100),rand:uniform(100)}, []]), % 2 is ID, 60 is supported weight
    timer:sleep(200),

    spawn(drone, start, [PrimaryManagerAddr, 3, 60, {rand:uniform(100),rand:uniform(100)}, []]), % 3 is ID, 60 is supported weight

    timer:sleep(4000),
    ok
.




% other test made
% - with no drones, ask one from the shell
% - with no drones, ask joinRequest from the shell

