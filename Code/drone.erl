%% @author Andrea
%% @doc @todo Add description to drone.


-module(drone).

%% ====================================================================
%% API functions
%% ====================================================================
-export([]).

join_Request(Manager_Server_Addr) ->
	Manager_Server_Addr ! {join_Request, self(), DroneID}.
  

%% ====================================================================
%% Internal functions
%% ====================================================================


