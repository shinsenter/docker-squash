# A distroless image has no shell, so it can only be squashed when the
# pre-squash scripts are skipped. The base image brings its own ENV, USER
# and WORKDIR.
# The digest pins gcr.io/distroless/static-debian12:nonroot so the expected
# output does not change.
FROM gcr.io/distroless/static-debian12:nonroot@sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab

# A typical entrypoint of a static binary.
ENTRYPOINT ["/app", "--config", "/etc/app/config.yaml"]
