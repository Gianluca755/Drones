%% @author Andrea
%% @doc @todo Add description to test5.
% c(manager,[debug_info]). c(broker,[debug_info]). c(client,[debug_info]). c(utils). c(drone,[debug_info]). c(election). c(test5,[debug_info]).

-module(test5).

%% ====================================================================
%% API functions
%% ====================================================================
-compile(export_all).



%% ====================================================================
%% Internal functions
%% ====================================================================

%% drones are near the package

startElection() ->

    P1 = {rand:uniform(3),rand:uniform(3)},
    P2 = {rand:uniform(7),rand:uniform(7)},
    P3 = {rand:uniform(11),rand:uniform(11)},
    io:format("Drone 1 Position: ~w~nDrone 2 Position: ~w~nDrone 3 Position: ~w~n", [P1, P2, P3]),

    Drone1 = spawn(drone, drone_Loop, [
                            self(),                                 % dummy pid for manager
                            1,                                      % drone ID
                            [],                                     % neighbours, it could ask the manager but not needed
                            60,                                     % supported weight
                            P1,      % initial position
                            500,                                    % battery life
                            [{10,10}],                              % recharging station
                            idle,                                   % status of the drone
                            0                                       % low battery count
                            ]
    ),

	Drone2 = spawn(drone, drone_Loop, [
                            self(),                                 % dummy pid for manager
                            2,                                      % drone ID
                            [],                                     % neighbours, it could ask the manager but not needed
                            60,                                     % supported weight
                            P2,      % initial position
                            500,                                    % battery life
                            [{10,10}],                              % recharging station
                            idle,                                   % status of the drone
                            0                                       % low battery count
                            ]
    ),

	Drone3 = spawn(drone, drone_Loop, [
                            self(),                                 % dummy pid for manager
                            3,                                      % drone ID
                            [],                                     % neighbours, it could ask the manager but not needed
                            60,                                     % supported weight
                            P3,      % initial position
                            500,                                    % battery life
                            [{10,10}],                              % recharging station
                            idle,                                   % status of the drone
                            0                                       % low battery count
                            ]
    ),

	Drone1 ! {newList,[Drone2,Drone3]},
	Drone2 ! {newList,[Drone1,Drone3]},
	Drone3 ! {newList,[Drone2,Drone1]},

	timer:sleep(2000),
	Drone1 ! {makeOrder,
                self(),     % dummy ClientAddress
	            1,          % ClientID
	            1,          % OrderID
	            {   {7,8},  % src
	                {8,7},  % dest
	                7       % weight
	            }
	         },


    %timer:sleep(1000),
	% simulate manager for the confirmation of the completation of the delivery
	receive {delivered, Pid, ClientID, OrderID, {}} -> Pid ! confirmDelivered end,
	ok
.




















