%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 16. May 2016 4:51 PM
%%%-------------------------------------------------------------------
-module(mesos_state).
-author("sdhillon").

-include_lib("kernel/include/inet.hrl").


-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%% API
-export([ip/0, domain_frag/1]).

-spec(ip() -> inet:ip4_address()).
ip() ->
    case dcos_ip() of
        false ->
            infer_ip();
        IP ->
            IP
    end.

infer_ip() ->
    ForeignIP = foreign_ip(),
    {ok, Socket} = gen_udp:open(0),
    inet_udp:connect(Socket, ForeignIP, 4),
    {ok, {Address, _LocalPort}} = inet:sockname(Socket),
    gen_udp:close(Socket),
    Address.

foreign_ip() ->
    case inet:gethostbyname("leader.mesos") of
        {ok, Hostent} ->
            [Addr | _] = Hostent#hostent.h_addr_list,
            Addr;
        _ ->
            {192, 88, 99, 0}
    end.


%% Regex borrowed from:
%% http://stackoverflow.com/questions/12794358/how-to-strip-all-blank-characters-in-a-string-in-erlang
-spec(dcos_ip() -> false | inet:ip4_address()).
dcos_ip() ->
    String = os:cmd("/opt/mesosphere/bin/detect_ip"),
    String1 = re:replace(String, "(^\\s+)|(\\s+$)", "", [global, {return, list}]),
    case inet:parse_ipv4_address(String1) of
        {ok, IP} ->
            IP;
        {error, einval} ->
            false
    end.

-spec(domain_frag([binary()]) -> binary()).

%% DomainFrag mangles the given name in order to produce a valid domain fragment.
%% A valid domain fragment will consist of one or more host name labels
domain_frag(BinaryString) when is_binary(BinaryString) ->
    Fragments = binary:split(BinaryString, <<".">>, [global, trim_all]),
    domain_frag(Fragments);
domain_frag(Fragments0) ->
    Fragments1 =
        lists:filter(
            fun
                (<<>>) -> false;
                (_) -> true
            end,
            Fragments0
        ),
    StringFragments0 = lists:map(fun label/1, Fragments1),
    list_to_binary(string:join(StringFragments0, ".")).


label(Fragment) when is_binary(Fragment) ->
    label(binary_to_list(Fragment));
label(FragmentStr) when is_list(FragmentStr) ->
    lists:reverse(label(start, FragmentStr, [])).

-type label_state() :: start | middle | terminate.
-spec(label(LabelState :: label_state(), RemainingChar :: string(), Acc :: string()) -> string()).
-define(ALLOWED_CHAR_GUARD(Char), (Char >= $a andalso Char =< $z) orelse (Char >= $0 andalso Char =< $9)).


%% When stripping from the accumulator left and right are reversed because it's backwards
label(_, [], Acc) ->
    string:strip(Acc, left, $-);
label(State, [Char0 | RestFragmentStr], Acc) when (Char0 >= $A andalso Char0 =< $Z) ->
    Char1 = Char0 - ($A - $a),
    label(State, [Char1 | RestFragmentStr], Acc);
label(start, FragmentStr = [Char | _RestFragmentStr], Acc) when ?ALLOWED_CHAR_GUARD(Char) ->
    label(middle, FragmentStr, Acc);
label(middle, FragmentStr, Acc0) when length(Acc0) > 62 ->
    Acc1 = string:strip(Acc0, left, $-),
    label(terminate, FragmentStr, Acc1);
label(middle, [Char | RestFragmentStr], Acc) when ?ALLOWED_CHAR_GUARD(Char) ->
    label(middle, RestFragmentStr, [Char | Acc]);
label(middle, [Char | RestFragmentStr], Acc) when Char == $- orelse Char == $_ orelse Char == $. ->
    label(middle, RestFragmentStr, [$- | Acc]);
label(terminate, _Str, Acc) when length(Acc) == 63 ->
    label(terminate, [], Acc);
label(terminate, [Char | RestFragmentStr], Acc) when ?ALLOWED_CHAR_GUARD(Char) ->
    label(terminate, RestFragmentStr, [Char | Acc]);
label(State, [_Char | RestFragmentStr], Acc) ->
    label(State, RestFragmentStr, Acc).


-ifdef(TEST).
remap_test() ->
    ?assertEqual("fdgsf---gs7-fgs--d7fddg-123", label("fd%gsf---gs7-f$gs--d7fddg-123")),
    ?assertEqual("4abc123", label("4abc123")),
    ?assertEqual("89fdgsf---gs7-fgs--d7fddg-123", label("89fdgsf---gs7-fgs--d7fddg-123")),
    ?assertEqual("fdgsf---gs7-fgs--d7fddg123456789012345678901234567890123456789", label("##fdgsf---gs7-fgs--d7fddg123456789012345678901234567890123456789-")),
    ?assertEqual("fdgsf---gs7-fgs--d7fddg1234567890123456789012345678901234567891", label("fd%gsf---gs7-f$gs--d7fddg123456789012345678901234567890123456789-123")),
    ?assertEqual("89fdgsf---gs7-fgs--d7fddg---123", label("89fdgsf---gs7-fgs--d7fddg---123")),
    ?assertEqual("fdgsf---gs7-fgs--d7fddg1234567890123456789012345678901234567891", label("%%fdgsf---gs7-fgs--d7fddg123456789012345678901234567890123456789---123")),
    ?assertEqual("4abc123", label("-4abc123")),
    ?assertEqual("fdgsf---gs7-fgs--d7fddg1234567890123456789012345678901234567891", label("$$fdgsf---gs7-fgs--d7fddg123456789012345678901234567890123456789-123")),
    ?assertEqual("89fdgsf---gs7-fgs--d7fddg", label("89fdgsf---gs7-fgs--d7fddg-")).
-endif.





