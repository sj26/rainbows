#!/bin/sh
# don't set nr_client for Rev, only _one_ app running at once :x
nr_client=${nr_client-2}
. ./test-lib.sh

rtmpfiles curl_out curl_err r_rot
rainbows_setup
rainbows -D sleep.ru -c $unicorn_config
rainbows_wait_start

# ensure our server is started and responding before signaling
curl -sSf http://$listen/ >/dev/null

start=$(date +%s)
for i in $(awk "BEGIN{for(i=0;i<$nr_client;++i) print i}" </dev/null)
do
	( curl -sSf http://$listen/2 >> $curl_out 2>> $curl_err ) &
done
check_stderr

rm -f $r_rot
mv $r_err $r_rot

kill -USR1 $(cat $pid)
wait_for_pid $r_err

dbgcat r_rot
dbgcat r_err

wait
echo elapsed=$(( $(date +%s) - $start ))
test ! -s $curl_err
test x"$(wc -l < $curl_out)" = x$nr_client
nr=$(sort < $curl_out | uniq | wc -l)

test "$nr" -eq 1
test x$(sort < $curl_out | uniq) = xHello
check_stderr
check_stderr $r_rot

before_rot=$(wc -c < $r_rot)
before_err=$(wc -c < $r_err)
curl -sSfv http://$listen/
after_rot=$(wc -c < $r_rot)
after_err=$(wc -c < $r_err)

test $after_rot -eq $before_rot && echo "before_rot -eq after_rot"
test $after_err -gt $before_err && echo "before_err -gt after_err"

kill $(cat $pid)
dbgcat r_err
check_stderr
check_stderr $r_rot
