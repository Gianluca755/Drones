%% @author Andrea
%% @doc @todo Add description to test5.
%c(manager,[debug_info]). c(broker,[debug_info]). c(client,[debug_info]). c(utils). c(drone,[debug_info]). c(election). c(test5).

-module(test5).

%% ====================================================================
%% API functions
%% ====================================================================
-export([]).
-compile(export_all).



%% ====================================================================
%% Internal functions
%% ====================================================================


startElection() ->


    Drone1 = spawn(drone, drone_Loop, [
                            a,
                            1,                                      % drone ID
                            [],                                     % neighbours, it could ask the manager but not needed
                            60,                                     % supported weight
                            {rand:uniform(100),rand:uniform(100)},  % initial position
                            500,                                    % battery life
                            [{10,10}],                              % recharging station
                            idle,                                   % status of the drone
                            3                                       % low battery count
                            ]
    ),
	
	Drone2 = spawn(drone, drone_Loop, [
                            a,
                            1,                                      % drone ID
                            [],                                     % neighbours, it could ask the manager but not needed
                            60,                                     % supported weight
                            {rand:uniform(100),rand:uniform(100)},  % initial position
                            500,                                    % battery life
                            [{10,10}],                               % recharging station
                            idle,                                   % status of the drone
                            3                                       % low battery count
                            ]
    ),

	Drone3 = spawn(drone, drone_Loop, [
                            a,
                            1,                                      % drone ID
                            [],                                     % neighbours, it could ask the manager but not needed
                            60,                                     % supported weight
                            {rand:uniform(100),rand:uniform(100)},  % initial position
                            500,                                    % battery life
                            [{10,10}],                               % recharging station
                            idle,                                   % status of the drone
                            3                                       % low battery count
                            ]
    ),
io:format("Drone ~w has been elected.~n", [Drone1]),
	Drone1 ! {newList,[Drone2,Drone3]},
	Drone2 ! {newList,[Drone1,Drone3]},
	Drone3 ! {newList,[Drone2,Drone1]},
	timer:sleep(2000),
	Drone1 ! {makeOrder,a ,2 ,3 ,{{7,8},{8,7},7}}
.