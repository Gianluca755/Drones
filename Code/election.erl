-module(election).

-export([initElection/8, nonInitElection/8]).

-export([checkResult/1, extractID_Addr_Distance/1]).
-export([findNearestRechargingStation/2,localDecisionAux/2]).
% receive msg with new order
% InitElection = spawn(drone, initElection, [self(), Neighbours]),
% InitElectionElection ! Msg

initElection(DroneAddr, DroneID, SupportedWeight, DronePosition, DroneBattery, Neighbours, RechargingStations, DroneStatus) ->

    % receive order from main process of the drone
    receive Order -> true
    end,

    % decompose order
    { makeOrder, _PidClient, ClientID, OrderID, {Source, Destination, Weight} } = Order,

    NewOrder = { election, self(), ClientID, OrderID, {Source, Destination, Weight} },

    sendToAll(NewOrder, Neighbours), % io:format("NeighInit~w~n", [Neighbours]),

    Results = receiveN(length(Neighbours), []), % io:format("ResultsInit: ~w~n", [Results]),

    if % case where the await of the response took too much time
        Results == 'EXIT' -> DroneAddr ! electionFailed, exit("err");
        true -> true
    end,

    SelectedResults = filter(Results, []),  % select only the result messages
	%io:format("selectedResultsInit: ~w~n", [SelectedResults]),
    Candidates = extract(SelectedResults,[]),
	%io:format("candidates: ~w~n", [Candidates]),

    % calculate distance needed by the delivery
    {S1, S2} = Source,
    {D1, D2} = Destination,
    DistanceOfDelivery = math:sqrt( math:pow( S1-D1, 2 ) + math:pow( S2-D2, 2 ) ),

    % calculate distance from drone to starting point of the delivery
    {P1, P2} = DronePosition,
    DistanceToPackage = math:sqrt( math:pow( S1-P1, 2 ) + math:pow( S2-P2, 2 ) ),

    % calculate distance from the finishing point of the delivery to the recharging station
    DistanceRecharging = findNearestRechargingStation(Destination, RechargingStations),

    %% make local decision %%

    % {-1, {}, 9999} is for the case when the drone can't deliver for some reason different from the weight
    % {-2, {}, 9999} is for the case when the drone can't deliver because the package weight too much

    if
        % drone busy, doesn't participate (implicit opt out)
        DroneStatus == {delivering, _, _, _, _, _} -> CompleteCandidates = Candidates ;

        % package too heavy, explicit opt out of this drone from the election
        Weight > SupportedWeight -> CompleteCandidates = [ {-2, {}, 9999}| Candidates] ;

        % if the drone can trasport the package, check if battery is not enough
        DroneBattery < DistanceOfDelivery + DistanceToPackage + DistanceRecharging ->
            CompleteCandidates = Candidates, % implicit opt out
            DroneAddr ! lowBattery ; % send a note the loop process of the drone

        % drone offer itself as candidate
        true -> CompleteCandidates = [ {DroneID, self(), DistanceToPackage}| Candidates]
    end,

    % choose the best between the initiator node and the neighbours
    DecidedDrone = localDecision(CompleteCandidates),

    {ElectedPid, ElectedDroneID, _ElectedDistance} = DecidedDrone,
	% io:format("DecidedDrone: ~w~n", [DecidedDrone]),
    % if there is no drone that can carry the weight check for -1, and alert main process of drone that will noitify the manager
    % ( the election doesn't flag the other cases where the fleet can't deliver because the manager will retry )
    if
        ElectedDroneID == -1 -> DroneAddr ! {excessiveWeight, ClientID, OrderID} ;
        true -> % in case of direct connection otherwise propagate in simil broadcast

                ElectedPid ! {elected, ClientID, OrderID, Source, Destination, Weight }
    end

.


% non initiator receive msg flag parent, propagate msg then wait for all the replies,
% choose the best option and send to parent, wait for decision to propagate.

nonInitElection(DroneAddr, DroneID, SupportedWeight, DronePosition, DroneBattery, Neighbours, RechargingStations, DroneStatus) ->
    receive Wave -> true
    end,

    { election, Parent, ClientID, OrderID, {Source, Destination, Weight} } = Wave, % select parent for the echo algo

    Children = list:delete(Parent, Neighbours),

    Wave2 = { election, self(), ClientID, OrderID, {Source, Destination, Weight} },
	%io:format("NeighNoInit~w~n", [Children]),

    sendToAll(Wave2, Children),
    Results = receiveN(length(Children), []),
	%io:format("ResultsNoInit: ~w~n", [Results]),
    if % case where the await of the response took too much time
        Results == 'EXIT' -> DroneAddr ! electionFailed, exit("err");
        true -> true
    end,

    SelectedResults = filter(Results, []),  % select only the result messages

    Candidates = extract(SelectedResults,[]),

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
        % drone busy, doesn't participate (implicit opt out)
        DroneStatus == {delivering, _, _, _, _, _} -> CompleteCandidates = Candidates ;

        % package too heavy, explicit opt out of this drone from the election
        Weight > SupportedWeight -> CompleteCandidates = [ {-2, {}, 9999}| Candidates] ;

        % if the drone can trasport the package, check if battery is not enough
        DroneBattery < DistanceOfDelivery + DistanceToPackage + DistanceRecharging ->
            CompleteCandidates = Candidates, % implicit opt out
            DroneAddr ! lowBattery ; % send a note the loop process of the drone

        % drone offer itself as candidate
        true -> CompleteCandidates = [ {DroneID, self(), DistanceToPackage}| Candidates]
    end,

    % choose the best between the initiator node and the neighbours
    DecidedDrone = localDecision(CompleteCandidates),
    {ElectedDroneID, ElectedPid, ElectedDistance} = DecidedDrone,

    % push decision to parent
    Parent ! {result, ElectedDroneID, ElectedPid, ElectedDistance},

    % the election decision will be communicated with direct connection, to this handler which will send the message to
    % the main process of the drone.
    % Otherwise a backpropagation system needs to be inserted here

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

filter(Received, Stored) ->
	 case Received of
		[]     -> Stored;
   		[X|Xs] -> {Type, _, _, _, _} = X,
    	if
       		Type == result -> filter(Xs, Stored ++ [X]);
        	true -> filter(Xs, Stored)
    	end
	 end
.

extract(Received, Stored)->
	case Received of
		[]     -> Stored;
   		[X|Xs] -> {result, ElectedDroneID, ElectedPid, Distance, {_ClientID, _OrderID, Weight} } = X,
				  extract(Xs, Stored ++ [{ElectedDroneID, ElectedPid, Distance}])
	end
.


receiveN(N, Received) ->

    if
        N == 0 -> Received;
        N > 0  -> receive {result, Addr, ClientID, OrderID, {Source, Destination, Weight}}= Msg -> receiveN(N-1, [Msg | Received])
                  after (3 * 60 * 1000) -> 'EXIT'
                  end
    end
.

% find min distance and in case of conflict choose the min ID
localDecision(List) ->
    localDecisionAux({-1, {}, 9999}, List)
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

% returns the distance between the drone position and the nearest recharging station
findNearestRechargingStation(Position, Stations) ->
    {P1, P2} = Position,
	if
		length(Stations) == 0 ->
			io:format("there are no recharging stations"), Stations;
		true->
			Distances = lists:map(
        	    fun(Station) -> {S1, S2} = Station, math:sqrt( math:pow( S1-P1, 2 ) + math:pow( S2-P2, 2 ) ) end,
        	    % end lambda func
        	    Stations     % list for the map
        	),
   			lists:min(Distances)
	end.

