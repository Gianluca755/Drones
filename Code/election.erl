

% receive msg with new order
InitElection = spawn(drone, initElection, [self(), Neighbours])
InitElectionElection ! Msg

initElection(DroneAddr, DronePosition, Neighbours) ->

    receive Order -> true
    end,

    sendToAll(Order, Neighbours), % CHANGE ORDER
    Results = receiveN(length(Neighbours), []),

    % choose the best beetween the initiator node and the neighbours

    % if needed propagate decision


    % if this node can't partecepate signal the loop process of the drone

.

% non initiator receive msg flag parent, propagate msg then wait for all the replies,
% choose the best option and send to parent, wait for decision to propagate.

nonInitElection() ->

.




sendToAll(Msg, Addresses) ->
    case Addresses of
    []      -> true;
    [X|Xs]  -> X ! Msg , sendToAll(Msg, Addresses)
    end
.

receiveN(N, Received) ->
    if
        N == 0 -> Received;
        N > 0  -> receive Msg -> receiveN(N-1, [Msg | Received])
                  end
    end
.

