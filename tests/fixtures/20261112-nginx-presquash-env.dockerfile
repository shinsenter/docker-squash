# A real image with a shell that sets its own pre-squash scripts.
# tests/test.sh uses it to check that the scripts of the image run by default
# and that the PRESQUASH_SCRIPTS build argument replaces them.
# The digest pins nginx:alpine-slim so the expected output does not change.
FROM nginx:alpine-slim@sha256:4c734d33ee731135dc9f2349914a34551c920f4451fca8bb05bf5880eb9079e8
ENV PRESQUASH_SCRIPTS="rm -rf /usr/lib/*"
