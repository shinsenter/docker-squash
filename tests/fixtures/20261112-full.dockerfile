# Every instruction that docker-squash restores.
FROM scratch

# PR #7: a line break in a label value broke the generated Dockerfile.
# A Dockerfile cannot hold a line break in a value, so test.sh passes it
# with --build-arg LF.
ARG LF
LABEL test.multiline="line 1${LF}${LF}line 3${LF}"

# PR #7: double quotes in a label value must be escaped.
LABEL test.quote="say \"hi\""

# PR #7: backslashes in a label value must be kept as they are.
LABEL test.backslash="C:\\dir\\file \\n"

# PR #7: a dollar sign in a label value must not be expanded as a variable.
LABEL test.dollar="costs \$HOME"

# A label key with a space needs quoting.
LABEL "test.key with space"="it's ok"

# PR #6: backslashes in an env value were doubled when the script ran in bash.
ENV TEST_BACKSLASH="C:\\dir\\file"

# Quotes, dollar signs and equal signs in an env value must be kept.
ENV TEST_SPECIAL="say \"hi\" for \$5, a=b"

# Ports with and without a protocol must be kept.
EXPOSE 80 8080/udp

# A volume path with a space must be kept as one path.
VOLUME ["/data dir", "/var/log"]

# Working directory, user and stop signal must be kept.
WORKDIR /app
USER 1000:1000
STOPSIGNAL SIGQUIT

# A custom shell must be kept in JSON form.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ENTRYPOINT and CMD in exec form must keep spaces, quotes and backslashes.
ENTRYPOINT ["/entry point", "--flag=\"x\""]
CMD ["arg 1", "$HOME", "back\\slash"]

# Every healthcheck option must be kept, with the command in shell form.
HEALTHCHECK --interval=5m --timeout=3s --start-period=10s --start-interval=2s --retries=5 \
    CMD curl --fail http://localhost/ || exit 1

# ONBUILD triggers must be kept and must not run while squashing.
# "ONBUILD COPY --from" is left out: BuildKit resolves its source when it reads
# the source image, so such an image cannot be squashed.
ONBUILD RUN echo "on build" && exit 1
ONBUILD COPY src /dst
