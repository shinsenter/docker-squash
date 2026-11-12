# ENTRYPOINT and CMD in shell form are stored with the default shell.
FROM scratch
ENTRYPOINT exec /bin/server --name "$HOSTNAME"
CMD echo "hello" && exit 0
