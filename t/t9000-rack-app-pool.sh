#!/bin/sh
. ./test-lib.sh

nr_client=30
rtmpfiles curl_out curl_err
rainbows_setup ThreadSpawn 50
APP_POOL_SIZE=4
APP_POOL_SIZE=$APP_POOL_SIZE rainbows -D t9000.ru -c $unicorn_config
rainbows_wait_start

start=$(date +%s)
for i in $(awk "BEGIN{for(i=0;i<$nr_client;++i) print i}" </dev/null)
do
	( curl -sSf http://$listen/ >> $curl_out 2>> $curl_err ) &
done
wait
echo elapsed=$(( $(date +%s) - $start ))
kill $(cat $pid)

test $APP_POOL_SIZE -eq $(sort < $curl_out | uniq | wc -l)
test ! -s $curl_err

check_stderr
