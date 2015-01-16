-module(erlaudio_escript).

-include_lib("erlaudio/include/erlaudio.hrl").

-export([main/1]).

main(["devices"|_]) ->
  Devices = [ Dev || Dev <- erlaudio:devices() ],
  io:put_chars(iolist_to_binary([
    [ integer_to_list(Dev#erlaudio_device.index), <<" ">>,
      Dev#erlaudio_device.name, <<"\n">>
    ]
    || Dev <- Devices
  ]));
main(["histogram"]) ->
  main(["histogram","-"]);
main(["histogram","-"|Rest]) ->
  #erlaudio_device{index=Index} = erlaudio:default_input_device(),
  main(["histogram", integer_to_list(Index)|Rest]);
main(["histogram", Input]) ->
  main(["histogram", Input, "30"]);
main(["histogram", Input, Time]) ->
  % Params = erlaudio:default_input_params(int16),
  Params = erlaudio:input_device_params(list_to_integer(Input), int16),
  {ok, Handle} = erlaudio:stream_open(Params, undefined, 48000.0, 2048, []),
  io:setopts([{encoding, unicode}]),
  ok = erlaudio:stream_start(Handle),
  erlang:send_after(list_to_integer(Time)*1000, self(), timeout),
  listen_loop(Handle);
main(["pipe"]) -> main(["pipe","-","-"]);
main(["pipe",Input]) -> main(["pipe",Input,"-"]);
main(["pipe","-"|Rest]) ->
  #erlaudio_device{index=Index} = erlaudio:default_input_device(),
  main(["pipe", integer_to_list(Index)|Rest]);
main(["pipe",Input,"-"|Rest]) ->
  #erlaudio_device{index=Index} = erlaudio:default_output_device(),
  main(["pipe", Input, integer_to_list(Index)|Rest]);
main(["pipe",Input,Output]) -> main(["pipe",Input,Output,"30"]);
main(["pipe",Input,Output,Time]) ->
  InputParams = erlaudio:input_device_params (list_to_integer(Input),  int16),
  OutputParams = erlaudio:output_device_params(list_to_integer(Output), int16),
  {ok, Handle} = erlaudio:stream_open(InputParams, OutputParams, 48000.0, 2048, []),
  io:setopts([{encoding, unicode}]),
  erlang:send_after(list_to_integer(Time)*1000, self(), timeout),
  ok = erlaudio:stream_start(Handle),
  listen_pipe(Handle);
main(["version"]) ->
  {_, Version} = erlaudio:portaudio_version(),
  io:put_chars([Version, "\n"]);
main(_) ->
  usage(),
  halt(1).

stream_write(_, _, 0) -> {error, out_of_tries};
stream_write(Handle, Data, Tries) ->
  case erlaudio:stream_write(Handle, Data) of
    ok -> ok;
    {error, toobig} ->
      timer:sleep(1),
      stream_write(Handle, Data, Tries-1)
  end.

listen_pipe(Handle) ->
  {ok, Data} = erlaudio:stream_recv(Handle),
  ok = stream_write(Handle, Data, 3),
  % hist(Data, {0,0,0,0,
  %             0,0,0,0,
  %             0,0,0,0,
  %             0,0,0,0}),
  case should_stop() of
    true -> ok;
    false -> listen_pipe(Handle)
  end.

listen_loop(Handle) ->
  {ok, Data} = erlaudio:stream_recv(Handle),
  hist(Data, {0,0,0,0,
              0,0,0,0,
              0,0,0,0,
              0,0,0,0}),
  % io:format("Got ~p bytes~n", [byte_size(Data)]),
  case should_stop() of
    true -> io:format("~nErlaudio Stream: ~p~n", [erlaudio:stream_close(Handle)]);
    false -> listen_loop(Handle)
  end.

char(C) when C < 0.1 -> <<"  "/utf8>>;
char(C) when C < 0.25 -> <<"▁ "/utf8>>;
char(C) when C < 0.4 -> <<"▂ "/utf8>>;
char(C) when C < 0.55 -> <<"▃ "/utf8>>;
char(C) when C < 0.70 -> <<"▅ "/utf8>>;
char(C) when C < 0.85 -> <<"▆ "/utf8>>;
char(_) -> <<"▇ "/utf8>>.

hist(<<>>, Hist) ->
  LHist = tuple_to_list(Hist),
  Max = lists:max(LHist),
  io:put_chars([$\r]),
  io:put_chars([char(I/Max) || I <- LHist]);
hist(<<L:16/signed,R:16/signed,Rest/binary>>, Hist) ->
  L1 = min(trunc(abs(L)/2048)+1, 16),
  R1 = min(trunc(abs(R)/2048)+1, 16),
  Hist1 = setelement(L1, Hist,  element(L1, Hist)+1),
  Hist2 = setelement(R1, Hist1, element(R1, Hist1)+1),
  hist(Rest, Hist2).

should_stop() ->
  receive timeout -> true
  after 0 -> false
  end.

usage() ->
  io:format("Usage: erlaudio [devices|histogram|version|usage]").