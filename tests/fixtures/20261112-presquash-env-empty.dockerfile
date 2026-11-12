# The source image turns the pre-squash step off with an empty
# ENV PRESQUASH_SCRIPTS. The default of the build argument must be empty too,
# instead of the default scripts of docker-squash.
FROM scratch
ENV PRESQUASH_SCRIPTS=""
