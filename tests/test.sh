#!/bin/sh
################################################################################
# The setups in this file belong to https://code.shin.company/docker-squash
# I appreciate you respecting my intellectual efforts in creating them.
# If you intend to copy or use ideas from this project, please credit properly.
# Author:  SHIN Company <shin@shin.company>
# License: https://code.shin.company/docker-squash/blob/main/LICENSE
################################################################################

BASE_DIR="$(git rev-parse --show-toplevel)"
TEST_DIR="$BASE_DIR/tests"

mkdir -p $TEST_DIR/logs/
rm   -rf $TEST_DIR/logs/*.{dockerfile,txt,log}
docker system prune -a --volumes -f

tests="$TEST_DIR/Dockerfile shinsenter/s6-overlay:latest shinsenter/php:latest alpine:latest ubuntu:latest debian:latest"
for test in $tests; do
    echo
    if [ ! -e $test ]; then
        name="$(echo $test | tr -c -s '[:alnum:]' '_')"
        tag="${test%:*}:squashed"
        # docker pull $test
    else
        name="$(basename $test | tr '[:upper:]' '[:lower:]')"
        tag="${name%.*}:squashed"
    fi

    echo "Squashing $test ($name)"
    if [[ "$@" = *"-p"* ]]; then
        $BASE_DIR/docker-squash.sh $test -t $tag "$@" > $TEST_DIR/logs/$name.dockerfile
    else
        $BASE_DIR/docker-squash.sh $test -t $tag "$@" | tee $TEST_DIR/logs/$name.txt
    fi
done

docker images | sort
