#!/bin/sh
. ./test-lib.sh

echo "simple HTTP connection keepalive/pipelining tests for $model"

tbase=$(expr "$T" : '^\(t....\)-').ru
test -f "$tbase" || die "$tbase missing for $T"

rainbows_setup
rainbows -D $tbase -c $unicorn_config
rainbows_wait_start

echo "single request"
curl -sSfv http://$listen/
dbgcat r_err

echo "two requests with keepalive"
curl -sSfv http://$listen/a http://$listen/b > $tmp 2>&1
dbgcat r_err
dbgcat tmp
grep 'Re-using existing connection' < $tmp

echo "pipelining partial requests"
req='GET / HTTP/1.1\r\nHost: example.com\r\n'
(
	printf "$req"'\r\n'"$req"
	cat $fifo > $tmp &
	sleep 1
	printf 'Connection: close\r\n\r\n'
	wait
	echo ok > $ok
) | socat - TCP:$listen > $fifo

dbgcat tmp

test 2 -eq $(grep '^HTTP/1.1' $tmp | wc -l)
test 2 -eq $(grep '^HTTP/1.1 200 OK' $tmp | wc -l)
test 1 -eq $(grep '^Connection: keep-alive' $tmp | wc -l)
test 1 -eq $(grep '^Connection: close' $tmp | wc -l)
test x"$(cat $ok)" = xok
check_stderr


echo "burst pipelining"
req='GET / HTTP/1.1\r\nHost: example.com\r\n'
(
	printf "$req"'\r\n'"$req"'Connection: close\r\n\r\n'
	cat $fifo > $tmp &
	wait
	echo ok > $ok
) | socat - TCP:$listen > $fifo

dbgcat tmp
dbgcat r_err

test 2 -eq $(grep '^HTTP/1.1' $tmp | wc -l)
test 2 -eq $(grep '^HTTP/1.1 200 OK' $tmp | wc -l)
test 1 -eq $(grep '^Connection: keep-alive' $tmp | wc -l)
test 1 -eq $(grep '^Connection: close' $tmp | wc -l)
test x"$(cat $ok)" = xok

check_stderr

echo "HTTP/0.9 request should not return headers"
(
	printf 'GET /\r\n'
	cat $fifo > $tmp &
	wait
	echo ok > $ok
) | socat - TCP:$listen > $fifo

dbgcat tmp
dbgcat r_err
echo "env.inspect should've put everything on one line"
test 1 -eq $(wc -l < $tmp)
! grep ^Connection: $tmp
! grep ^HTTP/ $tmp

kill $(cat $pid)
