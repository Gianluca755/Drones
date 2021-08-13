


% receive msg with new order
InitElection = spawn(drone, initElection, [self(), Neighbours])
InitElectionElection ! Msg

initElection(DroneAddr, DronePosition, Neighbours) ->

    receive Order -> true
    end,

    sendToAll(Order, Neighbours), % CHANGE THE ORDER INFO
    Results = receiveN(length(Neighbours), []),

    % choose the best between the initiator node and the neighbours

    % if this node can't partecepate due to low battery power, send a note the loop process of the drone


    % if needed propagate decision

.

% non initiator receive msg flag parent, propagate msg then wait for all the replies,
% choose the best option and send to parent, wait for decision to propagate.

nonInitElection(DroneAddr, DronePosition, Neighbours) ->
    receive Wave ->
    end,

    Children = list:delete(Parent, Neighbours),

    sendToAll(Wave, Children),
    Results = receiveN(length(Children), []),

    % make local decision

    % if this node can't partecepate due to low battery power, send a note the loop process of the drone


    % push decision to parent

    % wait for propagation of the election result



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

