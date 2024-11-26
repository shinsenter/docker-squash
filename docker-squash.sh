#!/bin/sh
################################################################################
# The setups in this file belong to https://code.shin.company/docker-squash
# I appreciate you respecting my intellectual efforts in creating them.
# If you intend to copy or use ideas from this project, please credit properly.
# Author:  SHIN Company <shin@shin.company>
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

Author:  SHIN Company <shin@shin.company>
License: https://code.shin.company/docker-squash/blob/main/LICENSE

EOF
}

upgrade() {
    local install=/usr/local/bin/docker-squash.sh
    sudo curl -L https://github.com/shinsenter/docker-squash/raw/main/docker-squash.sh \
        -o $install && chmod +x $install && $install -h
}

docker_tag_id() {
    docker images --format '{{.Repository}}:{{.Tag}}\t{{.ID}}' 2>/dev/null | grep -wi "$@" | sort | head -n1
}

docker_config() {
    docker image inspect --format='{{json .Config}}' "$1" | tr -d '[:cntrl:]'
}

parse_config() {
    local id="$1"; shift; docker_config "$id" | jq -r "$@"
}

get_name()        { docker_tag_id "$1" | awk '{printf $1}'; }
get_id()          { docker_tag_id "$1" | awk '{printf $2}'; }
get_labels()      { parse_config "$1" '.Labels // empty|to_entries|map("LABEL \(.key)=\"\(.value)\"")|.[]'; }
get_shell()       { parse_config "$1" '.Shell // empty|@json'; }
get_envs()        { parse_config "$1" '.Env // empty|map(gsub("\\\\"; "\\\\\\\\"))|sort|.[]|capture("(?<key>[^=]+)=(?<value>.*)")|"ENV \(.key)=\"\(.value)\""'; }
get_onbuilds()    { parse_config "$1" '.OnBuild // empty|map("ONBUILD \(.)")|.[]'; }
get_exposes()     { parse_config "$1" '.ExposedPorts // empty|keys|map("EXPOSE \(.)")|.[]'; }
get_workdir()     { parse_config "$1" '.WorkingDir // empty'; }
get_user()        { parse_config "$1" '.User // empty'; }
get_volumes()     { parse_config "$1" '.Volumes // empty|keys|map("VOLUME \"\(.)\"")|sort|.[]'; }
get_entrypoint()  { parse_config "$1" '.Entrypoint // empty|@json'; }
get_cmd()         { parse_config "$1" '.Cmd // empty|@json'; }
get_stopsignal()  { parse_config "$1" '.StopSignal // empty'; }
get_healthcheck() { parse_config "$1" '.Healthcheck // empty|(
    (if .Interval    then "--interval="+(.Interval|tonumber/1000000000|tostring)+"s " else "" end) +
    (if .Timeout     then "--timeout="+(.Timeout|tonumber/1000000000|tostring)+"s " else "" end) +
    (if .StartPeriod then "--start-period="+(.StartPeriod|tonumber/1000000000|tostring)+"s " else "" end) +
    (if .StartInterval then "--start-interval="+(.StartInterval|tonumber/1000000000|tostring)+"s " else "" end) +
    (if .Retries    then "--retries="+(.Retries|tostring)+" " else "" end) +
    (.Test[0]|sub("-SHELL";"")) + " " + .Test[1]
)'; }

generate() {
    local id="$(get_id "$1")"

    if [ -z "$id" ]; then
        echo "Invalid docker image: $1. Please build or pull the image first." >&2
        exit 1
    fi

    local base="scratch"
    local alias="temp-$id"
    local tag="$(get_name "$id")"
    local labels="$(get_labels "$id")"
    local shell="$(get_shell "$id")"
    local envs="$(get_envs "$id")"
    local onbuilds="$(get_onbuilds "$id")"
    local exposes="$(get_exposes "$id")"
    local workdir="$(get_workdir "$id")"
    local user="$(get_user "$id")"
    local volumes="$(get_volumes "$id")"
    local entrypoint="$(get_entrypoint "$id")"
    local cmd="$(get_cmd "$id")"
    local stopsignal="$(get_stopsignal "$id")"
    local healthcheck="$(get_healthcheck "$id")"

    awk NF <<Dockerfile
# syntax=docker/dockerfile:1

################################################################################
# Base image: $tag (Image ID: $id)
# Created at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Created by: https://code.shin.company/docker-squash

################################################################################
# Enable SBOM attestations
# See: https://docs.docker.com/build/attestations/sbom/
ARG BUILDKIT_SBOM_SCAN_CONTEXT=true
ARG BUILDKIT_SBOM_SCAN_STAGE=true

################################################################################
# CLEANING UP THE SOURCE IMAGE. ################################################
FROM $tag AS $alias
# Pre-squash scripts may be useful to clean the source image before squashing.
# Use build argument to add your pre-squash scripts, and run them in this stage.
# Example:
#   ${0##*/} $tag --build-arg PRESQUASH_SCRIPTS="rm -rf /tmp/*"
#   ${0##*/} $tag --build-arg PRESQUASH_SCRIPTS="/path/to/script.sh"
ARG PRESQUASH_SCRIPTS="\${PRESQUASH_SCRIPTS:-rm -rf /tmp/* /usr/share/doc/* /var/cache/* /var/lib/apt/lists/* /var/log/*}"
RUN [ ! -z "\$PRESQUASH_SCRIPTS" ] && sh -c "\$PRESQUASH_SCRIPTS" || true

################################################################################
# BUILDING SQUASHED IMAGE FROM SCRATCH. ########################################
FROM $base AS squashed-$id
COPY --link --from=$alias / /
$(if [ -n "$labels" ];      then echo "$labels"; fi)
$(if [ -n "$shell" ];       then echo "SHELL $shell"; fi)
$(if [ -n "$envs" ];        then echo "$envs"; fi)
$(if [ -n "$onbuilds" ];    then echo "$onbuilds"; fi)
$(if [ -n "$exposes" ];     then echo "$exposes"; fi)
$(if [ -n "$workdir" ];     then echo "WORKDIR $workdir"; fi)
$(if [ -n "$user" ];        then echo "USER $user"; fi)
$(if [ -n "$volumes" ];     then echo "$volumes"; fi)
$(if [ -n "$entrypoint" ];  then echo "ENTRYPOINT $entrypoint"; fi)
$(if [ -n "$cmd" ];         then echo "CMD $cmd"; fi)
$(if [ -n "$stopsignal" ];  then echo "STOPSIGNAL $stopsignal"; fi)
$(if [ -n "$healthcheck" ]; then echo "HEALTHCHECK $healthcheck"; fi)
# FINISH. ######################################################################
################################################################################
Dockerfile
}

# Parse arguments
################################################################################

# Show usage if no arguments are passed
if [ $# -eq 0 ]; then
    usage >&2
    exit 1
fi

for a; do
    shift
    case "$a" in
    --help | -h) usage >&2; exit 0; ;;
    --upgrade | upgrade | -u) upgrade; exit 0; ;;
    --print* | -p*) print=1 ;;
    *) set -- "$@" "$a" ;;
    esac
done

dockerfile="$1"
cleanup=0
shift

# Check Source Image / Build From Dockerfile
################################################################################

# Enable debug mode
if [ ! -z "$DEBUG" ]; then set -ex; fi

# Build tempoprary image from Dockerfile
if [ -f "$dockerfile" ]; then
    hash="$(sha256sum "$dockerfile")/$(echo $@ | sha256sum)"
    temptag="docker-squash-build-$(echo $hash | sha256sum | head -c 8)"
    context="$(dirname "$dockerfile")"

    if ! docker build -f "$dockerfile" "$context" "$@" -t "$temptag"; then
        echo "Failed to build image from $dockerfile." >&2
        exit 1
    fi

    source="$temptag"
    cleanup="${CLEAR_TEMP_BUILD:-1}"
else
    # try pulling the docker image from Docker Hub
    if [ -z "$(get_name "$dockerfile")" ]; then
        docker pull "$dockerfile" 2>&1
    fi

    source="$(get_name "$dockerfile")"
fi

# Check if source exists
if [ -z "$source" ]; then
    echo "Invalid image data from '$dockerfile'. Please build or pull the image first." >&2
    exit 1
fi

# Squash / Output to New Dockerfile
################################################################################

# Print Dockerfile to stdout
if [ ! -z "$print" ]; then
    generate "$source"
    exit 0
fi

# Use Docker buildx if available
BUILD_CMD="docker build"
if docker buildx version &>/dev/null; then
    BUILD_CMD="docker buildx build"
fi

# Squash image to single layer
echo "Start squashing the image $source"
echo "  Build options: $@"
generate "$source" | $BUILD_CMD "$@" -
[ "$cleanup" -eq 1 ] && docker image rm -f "$source"
echo "Done."
