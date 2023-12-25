#!/bin/sh
# This file belongs to the project https://code.shin.company/docker-squash
# Author:  Shin <shin@shin.company>
# License: https://code.shin.company/docker-squash/blob/main/LICENSE
################################################################################

BASE_DIR="$(git rev-parse --show-toplevel)"
TEST_DIR="$BASE_DIR/tests"

mkdir -p $TEST_DIR/logs/
rm   -rf $TEST_DIR/logs/*.{dockerfile,txt,log}

tests="alpine:latest ubuntu:latest debian:latest shinsenter/php:latest"
for test in $tests; do
    name="$(echo $test | tr -c -s '[:alnum:]' '_')"
    tag="${test%:*}:squashed"
    docker pull $test

    echo "Squashing $test"
    $BASE_DIR/docker-squash.sh --print $test -t $tag > $TEST_DIR/logs/$name.dockerfile
    # $BASE_DIR/docker-squash.sh $test -t $tag | tee $TEST_DIR/logs/$name.txt
done
