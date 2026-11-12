#!/bin/sh
################################################################################
# The setups in this file belong to https://code.shin.company/docker-squash
# I appreciate you respecting my intellectual efforts in creating them.
# If you intend to copy or use ideas from this project, please credit properly.
# Author:  SHIN Company <shin@shin.company>
# License: https://code.shin.company/docker-squash/blob/main/LICENSE
################################################################################
# Tests docker-squash.sh with every pair of files in tests/fixtures:
#
#   <YYYYMMDD>-<name>.dockerfile   The Dockerfile of the source image.
#   <YYYYMMDD>-<name>.out.txt      The instructions docker-squash.sh must print.
#
# A test passes only when "docker-squash.sh <file>.dockerfile --print" prints
# exactly the instructions of <file>.out.txt. Comment lines are ignored.
# Two values change on every run and are replaced before comparing:
# the temporary image name (<image>) and the image ID (<id>).
#
# Each printed Dockerfile is also built, to check that the squashed image
# keeps the metadata of its source image.
#
# The tests start no container: only the metadata of the images is read with
# "docker image inspect". Fixtures start FROM scratch, or from a registry image
# pinned by digest so that the expected output does not change.
#
# Usage: tests/test.sh [--update]
#
#   --update   Write the printed instructions to the .out.txt files instead of
#              comparing them. Review the changes before committing.
#
# The result of each assertion and the totals go to stdout.
# The output of every command goes to tests/logs/test.log.
# The exit code is 0 when all assertions pass.
################################################################################

cd "$(dirname "$0")/.." || exit 1

SQUASH="./docker-squash.sh"
RESULT="docker-squash-result"
SHELLS="sh bash dash"
LOG="tests/logs/test.log"
LF='
'

# Use the Dockerfile frontend built into BuildKit instead of pulling one.
export DOCKERFILE_SYNTAX=

# The metadata to compare. Docker keeps the order of everything but ENV,
# and reports an unset working directory as "/" after a build.
FIELDS='{
    Labels, OnBuild, ExposedPorts, Volumes, User, StopSignal, Shell,
    Entrypoint, Cmd, Healthcheck,
    Env: (.Env // [] | sort),
    WorkingDir: (.WorkingDir // "" | if . == "" then "/" else . end)
}'

# ASSERTIONS
################################################################################

passed=0
failed=0

log()  { printf '%s\n' "$@" >>"$LOG"; }
pass() { passed=$((passed + 1)); echo "ok   - $1"; log "ok   - $1" ""; }
fail() { failed=$((failed + 1)); echo "FAIL - $1"; log "FAIL - $1" ""; }

# assert_success <name> <command...>: the command exits with 0.
assert_success() {
    local name="$1"; shift
    log "### $name" "\$ $*"
    if "$@" >>"$LOG" 2>&1; then pass "$name"; else fail "$name"; fi
}

# assert_failure <name> <command...>: the command exits with a non-zero code.
assert_failure() {
    local name="$1"; shift
    log "### $name" "\$ $*"
    if "$@" >>"$LOG" 2>&1; then fail "$name"; else pass "$name"; fi
}

# assert_equal <name> <expected> <actual>: both values are equal and not empty.
assert_equal() {
    log "### $1"
    if [ -n "$2" ] && [ "$2" = "$3" ]; then
        pass "$1"
    else
        log "--- expected" "$2" "--- actual" "$3"
        fail "$1"
    fi
}

# assert_contains <name> <text> <part>: the text contains the part.
assert_contains() {
    log "### $1"
    case "$2" in
    *"$3"*) pass "$1" ;;
    *) log "--- text" "$2" "--- does not contain" "$3"; fail "$1" ;;
    esac
}

# HELPERS
################################################################################

metadata() {
    docker image inspect --format '{{json .Config}}' "$1" 2>>"$LOG" | jq -S "$FIELDS"
}

size() {
    docker image inspect --format '{{.Size}}' "$1" 2>>"$LOG"
}

# source_image <dockerfile>: builds the fixture and prints the image name.
source_image() {
    sh "$SQUASH" "$1" --print --build-arg "LF=$LF" 2>>"$LOG" |
        sed -n 's/^# Base image: \(.*\) (Image ID.*/\1/p'
}

# Keeps the instructions only and replaces the values that change on every run.
instructions() {
    grep -v '^#' | sed -E \
        -e 's/docker-squash-build-[0-9a-f]+:latest/<image>/g' \
        -e 's/(temp-|squashed-)[0-9a-f]{12}/\1<id>/g'
}

remove_images() {
    docker image rm -f $(docker images -q "docker-squash-build-*") \
        $(docker images -q "$RESULT") >/dev/null 2>&1
}

# TESTS
################################################################################

mkdir -p "${LOG%/*}"
: >"$LOG"
remove_images

# The usage text is read from the comment block at the top of the script.
assert_contains "usage is printed with -h" "$(sh "$SQUASH" -h 2>&1)" "Usage: docker-squash.sh <source_image>"
assert_failure  "no argument fails" sh "$SQUASH"

for dockerfile in tests/fixtures/*.dockerfile; do
    expected="${dockerfile%.dockerfile}.out.txt"
    name="${dockerfile##*/}"
    name="${name%.dockerfile}"

    for shell in $SHELLS; do
        [ -x "$(command -v "$shell")" ] || continue

        # Print the Dockerfile. This also builds the temporary source image.
        log "\$ $shell $SQUASH $dockerfile --print"
        printed="$("$shell" "$SQUASH" "$dockerfile" --print --build-arg "LF=$LF" 2>>"$LOG")"
        source="$(printf '%s\n' "$printed" | sed -n 's/^# Base image: \(.*\) (Image ID.*/\1/p')"
        printed="$(printf '%s\n' "$printed" | instructions)"

        if [ "$1" = "--update" ] && [ "$shell" = "sh" ]; then
            printf '%s\n' "$printed" >"$expected"
        fi

        assert_equal "$name: printed instructions match ${expected##*/} ($shell)" \
            "$(instructions <"$expected" 2>>"$LOG")" "$printed"

        # Build the printed Dockerfile. The pre-squash scripts are skipped,
        # because scratch and distroless images have no shell.
        assert_success "$name: squash ($shell)" \
            "$shell" "$SQUASH" "$source" -t "$RESULT:$name" --build-arg PRESQUASH_SCRIPTS=
        assert_equal "$name: metadata is kept ($shell)" \
            "$(metadata "$source")" "$(metadata "$RESULT:$name")"
        docker image rm -f "$RESULT:$name" >/dev/null 2>&1
    done
done

# The generated Dockerfile must pass the build checks of the Dockerfile frontend.
# Only this small fixture is checked: "docker buildx build --check" crashed the
# Docker daemon (BuildKit 0.34.0) with the output of the "full" fixture.
source="$(source_image tests/fixtures/20261112-shell-form.dockerfile)"
sh "$SQUASH" "$source" --print >"${LOG%/*}/check.dockerfile" 2>>"$LOG"
assert_success "generated Dockerfile passes build checks" \
    docker buildx build --check - <"${LOG%/*}/check.dockerfile"

# A failed build must fail the script. The default pre-squash scripts need
# a shell, which a scratch image does not have.
assert_failure "failed build returns a non-zero exit code" \
    sh "$SQUASH" "$source" -t "$RESULT:failure"

# The pre-squash scripts must run in an image with a shell: the default scripts
# keep the metadata, and scripts that remove files make the image smaller.
source="$(source_image tests/fixtures/20261112-nginx-healthcheck-onbuild.dockerfile)"
assert_success "pre-squash: squash with the default scripts" \
    sh "$SQUASH" "$source" -t "$RESULT:default"
assert_equal "pre-squash: metadata is kept with the default scripts" \
    "$(metadata "$source")" "$(metadata "$RESULT:default")"
assert_success "pre-squash: squash with scripts that remove files" \
    sh "$SQUASH" "$source" -t "$RESULT:removed" --build-arg PRESQUASH_SCRIPTS='rm -rf /usr/lib/* /usr/share/*'
assert_success "pre-squash: removing files makes the image smaller" \
    [ "$(size "$RESULT:removed")" -lt "$(size "$RESULT:default")" ]

remove_images

# RESULT
################################################################################

echo
echo "Passed: $passed, failed: $failed (details: $LOG)"
[ "$failed" -eq 0 ]
