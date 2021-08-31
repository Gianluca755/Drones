-module(test4).
-export([startRecharge/0]).

% c(manager,[debug_info]). c(broker,[debug_info]). c(client,[debug_info]). c(utils). c(drone,[debug_info]). c("../Tests/test4", [debug_info]).

startRecharge() ->

    ElectionTable = ets:new(electionTable, [set, public]),

    Drone1 = spawn(drone, drone_Loop, [
                            self(),                                 % dummy manager address
                            1,                                      % drone ID
                            [],                                     % neighbours, it could ask the manager but not needed
                            60,                                     % supported weight
                            {7,7},                                  % initial position
                            500,                                    % battery life
                            [{10,10}],                              % recharging station
                            idle,                                   % status of the drone
                            3,                                      % low battery count
                            ElectionTable
                            ]
    ),

    timer:sleep(200),
    Drone1 ! lowBattery,
    timer:sleep(8000)
.
