# A web server image extended with a healthcheck and an ONBUILD trigger.
# The base image brings its own LABEL, ENV, EXPOSE, STOPSIGNAL, ENTRYPOINT and CMD.
# The digest pins nginx:alpine-slim so the expected output does not change.
FROM nginx:alpine-slim@sha256:4c734d33ee731135dc9f2349914a34551c920f4451fca8bb05bf5880eb9079e8

# The healthcheck options and its shell command must be kept.
HEALTHCHECK --interval=5m --timeout=3s CMD wget -q -O /dev/null http://localhost/ || exit 1

# The trigger must be kept and must not run while squashing.
ONBUILD RUN apk upgrade --no-cache
