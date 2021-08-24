% test 1
-module(test1).
-compile(export_all).

% c(manager). c(broker). c(client). c(utils).

% query of a non existing order
% ...


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

    PidClient = spawn(client, loopClient, [55, PrimaryBrokerAddr, BckBrokerAddr, 0]),
    io:format("PidClient: ~w~n", [PidClient]),

    PidClient ! makeOrder,
    timer:sleep(2000),
    PidClient ! {statusOrder, 0}, % orderID = 0 for first order
    ok
.

% make order with some drones
% ...
