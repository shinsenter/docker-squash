#!/bin/sh
################################################################################
# The setups in this file belong to https://code.shin.company/docker-squash
# I appreciate you respecting my intellectual efforts in creating them.
# If you intend to copy or use ideas from this project, please credit properly.
# Author:  SHIN Company <shin@shin.company>
# License: https://code.shin.company/docker-squash/blob/main/LICENSE
################################################################################
# Combines Docker image layers into a single layer, reducing storage space
# and improving runtime performance by decreasing mount points.
#
# Usage: docker-squash.sh <source_image> [build_options]
#
#   Arguments:
#     source_image   The original image ID or name:tag to be squashed.
#                    An absolute path to your Dockerfile can also be used.
#     build_options  Optional Docker build options like --build-arg, --label, etc.
#
#   Env Variables:
#     DOCKERFILE_SYNTAX
#                    Defaults to docker/dockerfile:1
#                    Normally there is no reason to change this unless you don't have access to docker.io from your network.
#                    Or want to use a local cache.
#                    Set it to an empty value to use the frontend built into BuildKit.
#
#   Build Arguments:
#     PRESQUASH_SCRIPTS
#                    Shell commands run in the source image before squashing.
#                    Defaults to ENV PRESQUASH_SCRIPTS of the source image.
#                    Without it, the default removes temporary files, docs,
#                    package lists, cache files and log files.
#                    Pass an empty value to skip this step.
#
# Author:  SHIN Company <shin@shin.company>
# License: https://code.shin.company/docker-squash/blob/main/LICENSE
################################################################################

trap 'kill 0' INT

# Check if Docker is installed, if not exit
if [ ! -x "$(command -v docker)" ]; then
    echo "Docker is not installed. Please install Docker and try again." >&2
    exit 1
fi

# Check if jq is installed, if not exit
if [ ! -x "$(command -v jq)" ]; then
    echo "jq is not installed. Please install jq and try again." >&2
    exit 1
fi

# HELPER FUNCTIONS
################################################################################

# Prints the usage text from the comment block at the top of this file.
usage() {
    echo
    awk 'NR > 8 && /^###/ { exit } NR > 8 { print substr($0, 3) }' "$0"
    echo
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

# Turns the image config (JSON) into Dockerfile instructions, one per line.
JQ_METADATA='
# Escapes a value for use inside double quotes in a Dockerfile.
# A Dockerfile cannot hold a line break in a value, so it is written as \n.
def replace(a; b): split(a) | join(b);
def esc: replace("\\"; "\\\\") | replace("\""; "\\\"") | replace("$"; "\\$") | replace("\n"; "\\n");

# Prints a non-empty string value, or a healthcheck duration option.
def text(name): select(. != null and . != "") | "\(name) \(.)";
def seconds(name; ns): if ns then "--\(name)=\(ns / 1000000000)s " else "" end;

# Test is ["NONE"], ["CMD-SHELL", "command"] or ["CMD", "arg", ...] (exec form).
def healthcheck:
    if .Test[0] == "NONE" then "NONE" else
        seconds("interval"; .Interval)
        + seconds("timeout"; .Timeout)
        + seconds("start-period"; .StartPeriod)
        + seconds("start-interval"; .StartInterval)
        + (if .Retries then "--retries=\(.Retries) " else "" end)
        + "CMD "
        + (if .Test[0] == "CMD-SHELL" then .Test[1] else .Test[1:] | tojson end)
    end;

(.Labels       // {} | to_entries[] | "LABEL \"\(.key | esc)\"=\"\(.value | esc)\""),
(.Shell        // empty | "SHELL \(tojson)"),
(.Env          // [] | sort[] | index("=") as $i | "ENV \(.[:$i])=\"\(.[$i + 1:] | esc)\""),
(.OnBuild      // [] | .[] | "ONBUILD \(.)"),
(.ExposedPorts // {} | keys[] | "EXPOSE \(.)"),
(.WorkingDir   | text("WORKDIR")),
(.User         | text("USER")),
(.Volumes      // {} | keys[] | "VOLUME \([.] | tojson)"),
(.Entrypoint   // empty | "ENTRYPOINT \(tojson)"),
(.Cmd          // empty | "CMD \(tojson)"),
(.StopSignal   | text("STOPSIGNAL")),
(.Healthcheck  // empty | select(.Test | length > 0) | "HEALTHCHECK " + healthcheck)
'

get_name()     { docker_tag_id "$1" | awk '{printf $1}'; }
get_id()       { docker_tag_id "$1" | awk '{printf $2}'; }
get_metadata() { docker_config "$1" | jq -r "$JQ_METADATA"; }

# Prints a --label build option for each label that has a line break.
# The output is quoted for the shell and meant to be used with eval.
get_multiline_labels() {
    docker_config "$1" | jq -r '.Labels // {} | to_entries[] | select(.value | contains("\n"))
        | "--label " + ("\(.key)=\(.value)" | @sh)'
}


generate() {
    local id="$(get_id "$1")"

    if [ -z "$id" ]; then
        echo "Invalid docker image: $1. Please build or pull the image first." >&2
        exit 1
    fi

    local base="scratch"
    local alias="temp-$id"
    local tag="$(get_name "$id")"
    local metadata="$(get_metadata "$id")"
    local envs="$(printf '%s\n' "$metadata" | grep '^ENV ')"
    # The source image can set its own pre-squash scripts with ENV PRESQUASH_SCRIPTS.
    # The value is already quoted for a Dockerfile.
    local presquash="$(printf '%s\n' "$envs" | sed -n 's/^ENV PRESQUASH_SCRIPTS=//p')"
    [ -n "$presquash" ] || presquash='"rm -rf /tmp/* /usr/share/doc/* /var/lib/apt/lists/*; find /var/cache /var/log -type f -delete"'

    awk NF <<Dockerfile
# syntax=${DOCKERFILE_SYNTAX-docker/dockerfile:1}

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
# Pre-squash scripts clean the source image before squashing.
# The default is ENV PRESQUASH_SCRIPTS of the source image. Without it,
# the default removes temporary files, docs, package lists, caches and logs,
# and keeps the directories of /var/cache and /var/log.
# Set your own scripts with a build argument. An empty value skips this step,
# which is required for images without a shell (scratch, distroless).
# Example:
#   ${0##*/} $tag --build-arg PRESQUASH_SCRIPTS="rm -rf /tmp/*"
#   ${0##*/} $tag --build-arg PRESQUASH_SCRIPTS="/path/to/script.sh"
#   ${0##*/} $tag --build-arg PRESQUASH_SCRIPTS=
ARG PRESQUASH_SCRIPTS=$presquash

################################################################################
# COPYING THE SOURCE IMAGE. ####################################################
# The files are copied instead of using "FROM $tag", because FROM would run
# the ONBUILD triggers of the source image.
FROM $base AS $alias
COPY --link --from=$tag / /

################################################################################
# CLEANING UP THE SOURCE IMAGE. ################################################
# The scripts run as root with the environment variables of the source image.
FROM $alias AS $alias-cleaned
$envs
ARG PRESQUASH_SCRIPTS
RUN sh -c "\$PRESQUASH_SCRIPTS" || true

# Use the cleaned stage only when there are pre-squash scripts.
FROM $alias\${PRESQUASH_SCRIPTS:+-cleaned} AS $alias-final

################################################################################
# BUILDING SQUASHED IMAGE FROM SCRATCH. ########################################
FROM $base AS squashed-$id
COPY --link --from=$alias-final / /
$metadata
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
if docker buildx version >/dev/null 2>&1; then
    BUILD_CMD="docker buildx build"
fi

# Squash image to single layer
echo "Start squashing the image $source"
echo "  Build options: $@"
# Labels with line breaks are passed as build options to keep their exact value.
eval "set -- $(get_multiline_labels "$source") \"\$@\""

generate "$source" | $BUILD_CMD "$@" -
status=$?
[ "$cleanup" -eq 1 ] && docker image rm -f "$source"

if [ "$status" -ne 0 ]; then
    echo "Failed to squash the image $source." >&2
    exit "$status"
fi

echo "Done."
