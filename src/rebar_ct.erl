%% -------------------------------------------------------------------
%%
%% rebar: Erlang Build Tools
%%
%% Copyright (c) 2009 Dave Smith (dizzyd@dizzyd.com)
%%
%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:
%%
%% The above copyright notice and this permission notice shall be included in
%% all copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%% THE SOFTWARE.
%% -------------------------------------------------------------------
%% 
%% Targets:
%% test - runs common test suites in ./test
%% int_test - runs suites in ./int_test
%% perf_test - runs suites inm ./perf_test
%%
%% Global options:
%% verbose=1 - show output from the common_test run as it goes
%% suite="foo"" - runs <test>/foo_SUITE
%% case="mycase" - runs individual test case foo_SUITE:mycase
%% -------------------------------------------------------------------
-module(rebar_ct).

-export([test/2,
         int_test/2,
         perf_test/2]).

-compile([export_all]).

-include("rebar.hrl").

%% ===================================================================
%% Public API
%% ===================================================================

test(Config, File) ->
    run_test_if_present("test", Config, File).

int_test(Config, File) ->
    run_test_if_present("int_test", Config, File).

perf_test(Config, File) ->
    run_test_if_present("perf_test", Config, File).

%% ===================================================================
%% Internal functions
%% ===================================================================
run_test_if_present(TestDir, Config, File) ->
    case filelib:is_dir(TestDir) of
        false ->
	    ?WARN("~s directory not present - skipping\n", [TestDir]),
            ok;
        true ->
	    run_test(TestDir, Config, File)
    end.

run_test(TestDir, Config, _File) ->
    {Cmd, RawLog} = make_cmd(TestDir, Config),
    clear_log(RawLog),
    case rebar_config:get_global(verbose, "0") of
	"0" ->
	    Output = " >> " ++ RawLog ++ " 2>&1";
	_ ->
	    Output = " 2>&1 | tee -a " ++ RawLog
    end,
    
    case rebar_utils:sh(Cmd ++ Output, [{"TESTDIR", TestDir}]) of
	ok ->
	    check_log(RawLog);
	{error, _Rc} ->
	    show_log(RawLog),
	    ?ERROR("Executing tests failed.\n", []),
	    ?FAIL
    end.


clear_log(RawLog) ->
    case filelib:ensure_dir("logs/index.html") of
	ok ->
	    NowStr = rebar_utils:now_str(),
	    LogHeader = "--- Test run on " ++ NowStr ++ " ---\n",
	    ok = file:write_file(RawLog, LogHeader);
	{error, Reason} ->
	    ?ERROR("Could not create log dir - ~p\n", [Reason]),
	    ?FAIL
    end.    

%% calling ct with erl does not return non-zero on failure - have to check
%% log results
check_log(RawLog) ->
    Msg = os:cmd("grep -e 'TEST COMPLETE' -e '{error,make_failed}' " ++ RawLog),
    MakeFailed = string:str(Msg, "{error,make_failed}") =/= 0,
    RunFailed = string:str(Msg, ", 0 failed") =:= 0,
    if
        MakeFailed ->
	    show_log(RawLog),
	    ?ERROR("Building tests failed\n",[]),
	    ?FAIL;

        RunFailed ->
	    show_log(RawLog),
	    ?ERROR("One or more tests failed\n",[]),
	    ?FAIL;

	true ->
	    ?CONSOLE("DONE. ~s\n", [Msg])
    end.
		
%% Show the log if it hasn't already been shown because verbose was on
show_log(RawLog) ->
    ?CONSOLE("Showing log\n", []),
    case rebar_config:get_global(verbose, "0") of
	"0" ->
	    {ok, Contents} = file:read_file(RawLog),
	    ?CONSOLE("~s", [Contents]);
	_ ->
	    ok
    end.

make_cmd(TestDir, _Config) ->
    {ok, Cwd} = file:get_cwd(),
    LogDir = filename:join(Cwd, "logs"),
    Ebin = filename:join(Cwd, "ebin"),
    IncludeDir = filename:join(Cwd, "include"),
    case filelib:is_dir(IncludeDir) of
	true ->
	    Include = " -I \"" ++ IncludeDir ++ "\"";
	false ->
	    Include = ""
    end,

    Cmd = lists:flatten(io_lib:format("erl " % should we expand ERL_PATH?
				      " -noshell -pa \"~s\" ~s"
				      " -s ct_run script_start -s erlang halt"
				      " -name test@~s"
				      " -logdir \"~s\""
				      " -env TEST_DIR \"~s\"",
				      [Ebin,
				       Include,
				       net_adm:localhost(), 
				       LogDir,
				       filename:join(Cwd, TestDir)])) ++
	get_ct_config_file(TestDir) ++
	get_config_file(TestDir) ++
	get_suite(TestDir) ++
	get_case(),
    RawLog = filename:join(LogDir, "raw.log"),
    {Cmd, RawLog}.
     

get_ct_config_file(TestDir) ->
    Config = filename:join(TestDir, "test.config"),
    case filelib:is_regular(Config) of
        false ->
            " ";
        true ->
            " -ct_config " ++ Config
    end.

get_config_file(TestDir) ->
    Config = filename:join(TestDir, "app.config"),
    case filelib:is_regular(Config) of
        false ->
            " ";
        true ->
            " -config " ++ Config
    end.

get_suite(TestDir) ->
    case rebar_config:get_global(suite, undefined) of
	undefined ->
	    " -dir " ++ TestDir;
	Suite ->
	    Filename = filename:join(TestDir, Suite ++ "_SUITE.erl"),
	    case filelib:is_regular(Filename) of
		false ->
		    ?ERROR("Suite ~s not found\n", [Suite]),
		    ?FAIL;
		true ->
		    " -suite " ++ Filename
	    end
    end.

get_case() ->
    case rebar_config:get_global('case', undefined) of
	undefined ->
	    "";
	Case ->
	    " -case " ++ Case
    end.
