-module(test4).
-compile(export_all).

% c(manager,[debug_info]). c(broker,[debug_info]). c(client,[debug_info]). c(utils). c(drone,[debug_info]).

startRecharge() ->

    PrimaryManagerAddr = spawn(manager, startPrimary, []),
    BckManagerAddr = spawn(manager, startBck, [PrimaryManagerAddr]),

    io:format("~nPrimary manager: ~w~n", [PrimaryManagerAddr]),
    io:format("Backup manager: ~w~n", [BckManagerAddr]),

    PrimaryBrokerAddr = spawn(broker, startPrimary, [PrimaryManagerAddr, BckManagerAddr]),
    BckBrokerAddr = spawn(broker, startBck, [PrimaryBrokerAddr, PrimaryManagerAddr, BckManagerAddr]),

    timer:sleep(200),

    Drone1 = spawn(drone, drone_Loop, [
                            PrimaryManagerAddr,
                            1,                                      % drone ID
                            [],                                     % neighbours, it could ask the manager but not needed
                            60,                                     % supported weight
                            {7,7},                                  % initial position
                            500,                                    % battery life
                            [{10,10}],                              % recharging station
                            idle,                                   % status of the drone
                            3                                       % low battery count
                            ]
    ),

    timer:sleep(200),
    Drone1 ! lowBattery,
    timer:sleep(20000)
.
