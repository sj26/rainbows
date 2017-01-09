#!/bin/sh
. ./test-lib.sh
case $model in
EventMachine) ;;
*)
	t_info "skipping $T since it's not compatible with $model"
	exit 0
	;;
esac

t_plan 5 "basic test for app.deferred? usage"

CONFIG_RU=app_deferred.ru

t_begin "setup and start" && {
	rainbows_setup
	rtmpfiles deferred_err deferred_out sync_err sync_out
	fifo=$fifo rainbows -D -c $unicorn_config $CONFIG_RU
	rainbows_wait_start
}

t_begin "synchronous requests run in the same thread" && {
	curl --no-buffer -sSf http://$listen/ >> $sync_out 2>> $sync_err &
	curl --no-buffer -sSf http://$listen/ >> $sync_out 2>> $sync_err &
	curl --no-buffer -sSf http://$listen/ >> $sync_out 2>> $sync_err &
	wait
	test ! -s $sync_err
	test 3 -eq "$(count_lines < $sync_out)"
	test 1 -eq "$(uniq < $sync_out | count_lines)"
}

t_begin "deferred requests run in a different thread" && {
	curl -sSf http://$listen/deferred >> $deferred_out 2>> $deferred_err
	test ! -s $deferred_err
	sync_thread="$(uniq < $sync_out)"
	test x"$(uniq < $deferred_out)" != x"$sync_thread"
}

t_begin "deferred requests run after graceful shutdown" && {
	# XXX sleeping 5s ought to be enough for SIGQUIT to arrive,
	# hard to tell with overloaded systems...
	s=5
	curl -sSf --no-buffer http://$listen/deferred$s \
		>$deferred_out 2>$deferred_err &
	curl_pid=$!
	msg="$(cat $fifo)"
	kill -QUIT $rainbows_pid
	test x"$msg" = x"sleeping ${s}s"
	wait $curl_pid # for curl to finish
	test $? -eq 0
	test ! -s $deferred_err
	test x"$(cat $deferred_out)" = 'xdeferred sleep'
}

t_begin "no errors in stderr" && check_stderr

t_done
