# A database image extended with a volume and a non-root user.
# The base image brings its own ENV, EXPOSE, WORKDIR, ENTRYPOINT and CMD.
# The digest pins redis:alpine so the expected output does not change.
FROM redis:alpine@sha256:7958cfbb9d152f87dadfbc89f1b0b15938f0b81ff8982feb327476f4911935c3

# The volume and the user must be kept.
VOLUME /data
USER redis
