#!/bin/sh
# This file belongs to the project https://code.shin.company/docker-squash
# Author:  Shin <shin@shin.company>
# License: https://code.shin.company/docker-squash/blob/main/LICENSE
################################################################################

# Check if Docker is installed, if not exit
if [ ! -x "$(command -v docker)" ]; then
    echo "Docker is not installed. Please install Docker and try again." >&2
    exit 1
fi

# HELPER FUNCTIONS
################################################################################

usage() {
  cat <<EOF

  Combines Docker image layers into a single layer, reducing storage space
  and improving runtime performance by decreasing mount points.

  Usage: ${0##*/} <source_image> [build_options]

  Arguments:
    source_image   The original image ID or name:tag to be squashed.
                   An absolute path to your Dockerfile can also be used.
    build_options  Optional Docker build options like --build-arg, --label, etc.

  Author:  Shin <shin@shin.company>
  License: https://code.shin.company/docker-squash/blob/main/LICENSE

EOF
}

docker_tag_id() {
    docker images --format '{{.Repository}}:{{.Tag}}\t{{.ID}}' 2>/dev/null | grep -F "$@" | head -n1
}

docker_config() {
    if [ "$JSON_CACHE" = "" ]; then
        JSON_CACHE="$(docker image inspect --format='{{json .Config}}' "$1")"
    fi
    printf '%s' "$JSON_CACHE" | tr -d '[:cntrl:]'
}

parse_config() {
    local id="$1"; shift
    docker_config "$id" | jq -r "$@"
}

get_name ()       { docker_tag_id "$1" | awk '{printf $1}'; }
get_id   ()       { docker_tag_id "$1" | awk '{printf $2}'; }
get_maintainer()  { parse_config  "$1" '.Labels["org.opencontainers.image.authors"] // empty'; }
get_labels()      { parse_config  "$1" '.Labels // empty|to_entries|map("LABEL \(.key)=\"\(.value)\"")|.[]'; }
get_shell()       { parse_config  "$1" '.Shell // empty|@json'; }
get_envs()        { parse_config  "$1" '.Env // empty|map(gsub("\\\\"; "\\\\\\\\"))|sort|.[]|capture("(?<key>[^=]+)=(?<value>.*)")|"ENV \(.key)=\"\(.value)\""'; }
get_exposes()     { parse_config  "$1" '.ExposedPorts // empty|keys|map("EXPOSE \(.)")|.[]'; }
get_workdir()     { parse_config  "$1" '.WorkingDir // empty'; }
get_user()        { parse_config  "$1" '.User // empty'; }
get_volumes()     { parse_config  "$1" '.Volumes // empty|keys|map("VOLUME \"\(.)\"")|sort|.[]'; }
get_entrypoint()  { parse_config  "$1" '.Entrypoint // empty|@json'; }
get_cmd()         { parse_config  "$1" '.Cmd // empty|@json'; }
get_stopsignal()  { parse_config  "$1" '.StopSignal // empty'; }
get_onbuilds()    { parse_config  "$1" '.OnBuild // empty|map("ONBUILD \(.)")|.[]'; }
get_healthcheck() { parse_config  "$1" '.Healthcheck // empty|(
    (if .Interval    then "--interval="+(.Interval|tonumber/1000000000|tostring)+"s " else "" end) +
    (if .Timeout     then "--timeout="+(.Timeout|tonumber/1000000000|tostring)+"s " else "" end) +
    (if .StartPeriod then "--start-period="+(.StartPeriod|tonumber/1000000000|tostring)+"s " else "" end) +
    (if .StartInterval then "--start-interval="+(.StartInterval|tonumber/1000000000|tostring)+"s " else "" end) +
    (if .Retries    then "--retries="+(.Retries|tostring)+" " else "" end) +
    (.Test[0]|sub("-SHELL";"")) + " " + .Test[1]
)'; }

dockerfile() {
    local id="$(get_id "$1")"

    if [ -z "$id" ]; then
        echo "Invalid docker image: $1. Please build or pull the image first." >&2
        exit 1
    fi

    JSON_CACHE=
    local base="scratch"
    local alias="temp-$id"
    local tag="$(get_name "$id")"
    local maintainer="$(get_maintainer "$id")"
    local labels="$(get_labels "$id")"
    local shell="$(get_shell "$id")"
    local envs="$(get_envs "$id")"
    local exposes="$(get_exposes "$id")"
    local workdir="$(get_workdir "$id")"
    local user="$(get_user "$id")"
    local volumes="$(get_volumes "$id")"
    local entrypoint="$(get_entrypoint "$id")"
    local cmd="$(get_cmd "$id")"
    local stopsignal="$(get_stopsignal "$id")"
    local onbuilds="$(get_onbuilds "$id")"
    local healthcheck="$(get_healthcheck "$id")"

    awk NF <<Dockerfile
# syntax=docker/dockerfile:1

################################################################################
# Base image: $tag (Image ID: $id)
# Created at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Created by: https://code.shin.company/docker-squash

################################################################################
# CLEANING UP THE SOURCE IMAGE. ################################################
FROM $tag AS $alias

# It may be useful to clean up the source image before squashing.
# Add your cleanup script via build argument and it will be executed here.
# Example:
#     ${0##*/} $tag --build-arg PRESQUASH_SCRIPTS="rm -rf /tmp/*"
#     ${0##*/} $tag --build-arg PRESQUASH_SCRIPTS="/path/to/script.sh"
ARG PRESQUASH_SCRIPTS
RUN \${PRESQUASH_SCRIPTS:-exit 0} || true

################################################################################
# BUILDING SQUASHED IMAGE FROM SCRATCH. ########################################
FROM $base as squashed-$id
COPY --link --from=$alias / /
$(if [ -n "$maintainer" ];  then echo "MAINTAINER $maintainer"; fi)
$(if [ -n "$labels" ];      then echo "$labels"; fi)
$(if [ -n "$shell" ];       then echo "SHELL $shell"; fi)
$(if [ -n "$envs" ];        then echo "$envs"; fi)
$(if [ -n "$exposes" ];     then echo "$exposes"; fi)
$(if [ -n "$workdir" ];     then echo "WORKDIR $workdir"; fi)
$(if [ -n "$user" ];        then echo "USER $user"; fi)
$(if [ -n "$volumes" ];     then echo "$volumes"; fi)
$(if [ -n "$entrypoint" ];  then echo "ENTRYPOINT $entrypoint"; fi)
$(if [ -n "$cmd" ];         then echo "CMD $cmd"; fi)
$(if [ -n "$stopsignal" ];  then echo "STOPSIGNAL $stopsignal"; fi)
$(if [ -n "$onbuilds" ];    then echo "$onbuilds"; fi)
$(if [ -n "$healthcheck" ]; then echo "HEALTHCHECK $healthcheck"; fi)
# FINISH. ######################################################################
################################################################################
Dockerfile
}

# Parse arguments
################################################################################

# Show usage if no arguments are passed
if [ $# -eq 0 ]; then usage >&2 ; exit 1; fi

for a; do
    shift
    case "$a" in
    --print*|-p*) print=1 ;;
    --help|-h)    usage >&2 ; exit 0 ;;
    *)            set -- "$@" "$a" ;;
    esac
done

# MAIN
################################################################################

if [ ! -z "$DEBUG" ]; then
    set -ex;
fi

dockerfile="$1"
cleanup=0
shift

if [ -f "$dockerfile" ]; then
    hash="$(sha256sum "$dockerfile")/$(echo $@ | sha256sum)"
    temptag="docker-squash-build-$(echo $hash | sha256sum | head -c 8)"
    context="$(dirname "$dockerfile")"

    # Build tempoprary image from Dockerfile
    docker build -f "$dockerfile" "$context" "$@" -t "$temptag"

    if [ $? -ne 0 ]; then
        echo "Failed to build image from $dockerfile." >&2
        exit 1
    fi

    source="$temptag"
    cleanup="${CLEAR_TEMP_BUILD:-1}"
else
    source="$(get_name "$dockerfile")"
fi

# Check if source exists
if [ -z "$source" ]; then
    echo "Invalid image data from '$dockerfile'. Please build or pull the image first." >&2
    exit 1
fi

# Print Dockerfile to stdout
if [ ! -z "$print" ]; then
    dockerfile "$source"
    exit 0
fi

# Squash image to single layer
echo "Start squashing the image $source"
echo "  Build options: $@"
dockerfile "$source" | docker build $@ -
[ "$cleanup" -eq 1 ] && docker image rm -f "$source"
echo "Done."
