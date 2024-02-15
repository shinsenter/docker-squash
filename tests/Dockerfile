FROM nginx:latest
HEALTHCHECK --interval=5m --timeout=3s CMD curl --fail http://nginx.host.com/ || exit 1
ONBUILD RUN apt-get update && apt-get upgrade -y
