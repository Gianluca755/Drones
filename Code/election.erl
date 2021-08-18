-module(election).

-export([initElection/7, nonInitElection/7]).

-export([checkResult/1, extractID_Addr_Distance/1]).

% receive msg with new order
% InitElection = spawn(drone, initElection, [self(), Neighbours]),
% InitElectionElection ! Msg

initElection(DroneAddr, DroneID, DroneCapacity, DronePosition, DroneBattery, Neighbours, RechargingStations) ->

    % receive order from main process of the drone
    receive Order -> true
    end,

    % decompose order
    { makeOrder, _PidClient, ClientID, OrderID, {Source, Destination, Weight} } = Order,

    NewOrder = {{ election, self(), ClientID, OrderID, {Source, Destination, Weight} }},
    sendToAll(NewOrder, Neighbours),

    Results = receiveN(length(Neighbours), []),

    if % case where the await of the response took too much time
        Results == 'EXIT' -> exit();
        true -> true
    end,

    SelectedResults = list:filter(checkResult, Results),  % select only the result messages

    Candidates = list:map(extractID_Addr_Distance, SelectedResults),

    % calculate distance needed by the delivery
    {S1, S2} = Source,
    {D1, D2} = Destination,
    DistanceOfDelivery = math:sqrt( math:pow( S1-D1, 2 ) + math:pow( S2-D2, 2 ) ),

    % calculate distance from drone to starting point of the delivery
    {P1, P2} = DronePosition,
    DistanceToPackage = math:sqrt( math:pow( S1-P1, 2 ) + math:pow( S2-P2, 2 ) ),

    % calculate distance from the finishing point of the delivery to the recharging station
    DistanceRecharging = findNearestRechargingStation( Destination, RechargingStations),

    % make local decision

    % {-1, 9999} is for the case when the drone can't deliver for some reason different from the weight
    % {-2, 9999} is for the case when the drone can't deliver because the package weight too much

    if
        % explicit opt out from the elction
        DroneCapacity < Weight -> CompleteCandidates = [ {-2, {}, 9999}| Candidates] ;

        % if the drone can trasport the package, check battery
        DroneBattery >= DistanceOfDelivery + DistanceToPackage + DistanceRecharging ->
            CompleteCandidates = [ {DroneID, self(), DistanceToPackage}| Candidates],
            % if this node can't partecepate due to low battery power, send a note the loop process of the drone
            DroneAddr ! lowBattery ;
        true -> CompleteCandidates = Candidates % doesn't have to explicitly opt out from the election because of the structure of localDecision (called below)
    end,

    % choose the best between the initiator node and the neighbours
    DecidedDrone = localDecision(CompleteCandidates),

    {ElectedDroneID, ElectedPid, _ElectedDistance} = DecidedDrone,

    % if there is no drone that can carry the weight check for -1, and alert main process of drone that will noitify the manager
    % ( the election doesn't flag the other cases where the fleet can't deliver because the manager will retry )
    if
        ElectedDroneID == -1 -> DroneAddr ! {excessiveWeight, ClientID, OrderID} ;
        true -> % in case of direct connection otherwise propagate in simil broadcast
                ElectedPid ! {elected, ClientID, OrderID, Source, Destination }
    end

.


% non initiator receive msg flag parent, propagate msg then wait for all the replies,
% choose the best option and send to parent, wait for decision to propagate.

nonInitElection(DroneAddr, DroneID, DroneCapacity, DronePosition, DroneBattery, Neighbours, RechargingStations) ->
    receive Wave -> true
    end,

    {{ election, Parent, ClientID, OrderID, {Source, Destination, Weight} }} = Wave, % select parent for the echo algo

    Children = list:delete(Parent, Neighbours),

    Wave2 = {{ election, self(), ClientID, OrderID, {Source, Destination, Weight} }},
    sendToAll(Wave2, Children),
    Results = receiveN(length(Children), []),

    if % case where the await of the response took too much time
        Results == 'EXIT' -> exit();
        true -> true
    end,

    SelectedResults = list:filter(checkResult, Results),  % select only the result messages

    Candidates = list:map(extractID_Addr_Distance, SelectedResults),

    % calculate distance needed by the delivery
    {S1, S2} = Source,
    {D1, D2} = Destination,
    DistanceOfDelivery = math:sqrt( math:pow( S1-D1, 2 ) + math:pow( S2-D2, 2 ) ),

    % calculate distance from drone to starting point of the delivery
    {P1, P2} = DronePosition,
    DistanceToPackage = math:sqrt( math:pow( S1-P1, 2 ) + math:pow( S2-P2, 2 ) ),

    % calculate distance from the finishing point of the delivery to the recharging station
    DistanceRecharging = findNearestRechargingStation( Destination, RechargingStations),

    % make local decision

    % {-1, 9999} is for the case when the drone can't deliver for some reason different from the weight
    % {-2, 9999} is for the case when the drone can't deliver because the package weight too much

    if
        % explicit opt out from the elction
        DroneCapacity < Weight -> CompleteCandidates = [ {-2, {}, 9999}| Candidates] ;

        % if the drone can trasport the package, check battery
        DroneBattery >= DistanceOfDelivery + DistanceToPackage + DistanceRecharging ->
            CompleteCandidates = [ {DroneID, self(), DistanceToPackage}| Candidates],
            % if this node can't partecepate due to low battery power, send a note the loop process of the drone
            DroneAddr ! lowBattery ;
        true -> CompleteCandidates = Candidates % doesn't have to explicitly opt out from the election because of the structure of localDecision (called below)
    end,

    % choose the best between the initiator node and the neighbours
    DecidedDrone = localDecision(CompleteCandidates),
    {ElectedDroneID, ElectedPid, ElectedDistance} = DecidedDrone,

    % push decision to parent
    Parent ! {result, ElectedDroneID, ElectedPid, ElectedDistance},

    % the election decision will be communicated with direct connection, otherwise a backpropagation needs to be inserted here

    receive {elected, ClientID, OrderID, Source, Destination } = MsgElection -> DroneAddr ! MsgElection % let the drone handle it
    after (3 * 60 * 1000) -> true % exit after 3m
    end
.


% map(fun(Pid) -> Pid ! Msg end, List)
sendToAll(Msg, Addresses) ->
    case Addresses of
    []      -> true;
    [X|Xs]  -> X ! Msg , sendToAll(Msg, Xs)
    end
.

receiveN(N, Received) ->
    if
        N == 0 -> Received;
        N > 0  -> receive Msg -> receiveN(N-1, [Msg | Received])
                  after (3 * 60 * 1000) -> 'EXIT'
                  end
    end
.

% find min distance and in case of conflict choose the min ID
localDecision(List) ->
    localDecisionAux({-1, 9999}, List)
    % {-1, 9999} is for the case when the drone can't deliver for some reason different from the weight
    % {-2, 9999} is for the case when the drone can't deliver because the package weight too much
    % in the way the function are build the send one have precedence while the first one is the default in the
    % case when the children of the node don't participate for some reason.
    % the fact that we have a default case means that the current drone doesn't have to explicitly opt out from the election
.


localDecisionAux(Best, List) -> % Best is a tuple of ID, Addr, distance, it's the minimum found so far
    case List of
    []     -> Best;
    [X|Xs] -> {ID, Addr, Distance} = X,
              {BestID, BestAddr, BestDistance} = Best,
              if
                Distance < BestDistance  -> NewID = ID, NewAddr = Addr, NewDistance = Distance ;

                Distance == BestDistance -> if
                                                    ID < BestID   -> NewID = ID, NewAddr = Addr, NewDistance = Distance ;
                                                    true          -> NewID = BestID, NewAddr = Addr, NewDistance = Distance
                                            end;

                % this case ignore the X because isn't better then the Best, and continue with recursion
                true -> NewID = BestID, NewAddr = BestAddr, NewDistance = BestDistance
              end,

              localDecisionAux({NewID, NewAddr, NewDistance}, Xs)
    end
.


checkResult(X) ->
    {Type, _, _, _, _} = X,
    if
        Type == result -> true;
        true -> false
    end
.


extractID_Addr_Distance(X) ->
    {result, ElectedDroneID, ElectedPid, Distance, {_ClientID, _OrderID} } = X,

    {ElectedDroneID, ElectedPid, Distance}
.

% returns the min distance to the recharging station
findNearestRechargingStation(Position, Stations) ->
    {P1, P2} = Position,

    Distances = list:map(
        fun(Station) -> {S1, S2} = Station, math:sqrt( math:pow( S1-P1, 2 ) + math:pow( S2-P2, 2 ) ) end,
        Stations
        ),

    list:min(Distances)

.

