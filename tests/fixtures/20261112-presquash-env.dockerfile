# The source image sets its own pre-squash scripts with ENV PRESQUASH_SCRIPTS.
# The value must become the default of the PRESQUASH_SCRIPTS build argument,
# with quotes and dollar signs kept, and must stay in the squashed image.
FROM scratch
ENV PRESQUASH_SCRIPTS="rm -rf /tmp/* \"\$HOME/.cache\"; find /var/log -type f -delete"
