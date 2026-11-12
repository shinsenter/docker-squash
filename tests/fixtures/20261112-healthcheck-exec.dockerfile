# HEALTHCHECK in exec form must keep every argument.
FROM scratch
HEALTHCHECK --interval=90s CMD ["/bin/check", "--url", "http://host/a b"]
