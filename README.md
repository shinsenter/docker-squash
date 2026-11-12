# docker-squash

A single shell script that squashes all layers of a Docker image into one layer and keeps the image metadata.

It is an alternative to the experimental `docker build --squash` option, which needs an experimental daemon and is not available with BuildKit.

## What it does

`docker-squash.sh` reads the metadata of the source image, writes a new Dockerfile from it, and builds that Dockerfile:

1. Copy all files of the source image into an empty stage.
2. Run the pre-squash scripts to remove files you do not need.
3. Copy the result into a new image `FROM scratch`, which gives a single layer.
4. Restore the metadata: `LABEL`, `ENV`, `EXPOSE`, `VOLUME`, `WORKDIR`, `USER`, `SHELL`, `ENTRYPOINT`, `CMD`, `STOPSIGNAL`, `HEALTHCHECK` and `ONBUILD`.

Files that an upper layer deleted or replaced no longer take space, and the pre-squash scripts remove files for real instead of hiding them in a new layer.

## Results

Measured on 2026-11-12 with Docker 29.9.2. Sizes come from `docker image inspect --format '{{.Size}}'`.

| Source image | Pre-squash scripts | Before | After | Layers |
|---|---|---|---|---|
| `nginx:latest` | default | 258MB | 251MB | 7 to 1 |
| `python:3.14` | default | 1618MB | 1505MB | 7 to 1 |
| `php:apache` | default | 740MB | 727MB | 14 to 2 |
| `php:apache` | remove build dependencies (see below) | 740MB | 367MB | 14 to 2 |

Squashing alone saves little on official images, because they are already built with few wasted layers. The large saving comes from removing files in the pre-squash step, such as compilers and `-dev` packages that are only needed at build time.

## Requirements

- Docker with BuildKit
- [jq](https://jqlang.org/)

## Download

```shell
sudo curl -sL https://github.com/shinsenter/docker-squash/raw/main/docker-squash.sh -o /usr/local/bin/docker-squash.sh
sudo chmod +x /usr/local/bin/docker-squash.sh
```

## Usage

```shell
docker-squash.sh <source_image> [docker build options]
```

- `source_image`: an image ID, a `name:tag`, or the path to a Dockerfile. An image that is not on your machine is pulled first.
- `docker build options`: any option of `docker build`, such as `-t`, `--build-arg`, `--label` or `--platform`.

| Option | Description |
|---|---|
| `--print`, `-p` | Print the generated Dockerfile instead of building it. |
| `--upgrade`, `-u` | Download the latest version of the script. |
| `--help`, `-h` | Show the usage. |

### Squash an image

```shell
docker pull nginx:latest
docker-squash.sh nginx:latest -t nginx:squashed
docker images nginx
```

### Remove files before squashing

The build argument `PRESQUASH_SCRIPTS` holds shell commands that run in the source image before squashing. They run as root, with the environment variables of the source image.

The default removes temporary files, docs, package lists, cache files and log files:

```shell
rm -rf /tmp/* /usr/share/doc/* /var/lib/apt/lists/*; find /var/cache /var/log -type f -delete
```

Set your own commands to remove more. This example removes the build dependencies of `php:apache` and brings it from 740MB to 367MB:

```shell
docker pull php:apache
docker-squash.sh php:apache -t php:apache-squashed \
    --build-arg PRESQUASH_SCRIPTS='rm -rf /tmp/* /var/lib/apt/lists/*; apt-get -y autoremove --purge $PHPIZE_DEPS *-dev'
```

Pass an empty value to skip this step. This is required for images without a shell, such as distroless images:

```shell
docker-squash.sh my-distroless-app:latest -t my-distroless-app:squashed --build-arg PRESQUASH_SCRIPTS=
```

### Squash an image for another platform

```shell
docker pull --platform linux/arm64 ubuntu:latest
docker-squash.sh ubuntu:latest -t ubuntu:squashed --platform linux/arm64
```

### Squash straight from a Dockerfile

The script builds the Dockerfile first, then squashes the result. The build options are used for both builds.

```shell
docker-squash.sh /home/my-project/Dockerfile -t my-project:squashed
```

### Review the generated Dockerfile

```shell
docker-squash.sh nginx:latest --print
```

### Environment variables

| Variable | Description |
|---|---|
| `DOCKERFILE_SYNTAX` | The Dockerfile frontend, `docker/dockerfile:1` by default. Change it when you cannot reach docker.io. Set it to an empty value to use the frontend built into BuildKit. |
| `CLEAR_TEMP_BUILD` | Set it to `0` to keep the temporary image built from a Dockerfile. |
| `DEBUG` | Set it to any value to trace the script. |

## Limitations

- A Dockerfile cannot hold a line break in a value. Labels with line breaks are kept exactly when the script builds the image. In the output of `--print`, and in `ENV` values, a line break is written as `\n`.
- `ENV` instructions are written in alphabetical order.
- An image with an `ONBUILD COPY --from=...` trigger cannot be squashed, because BuildKit resolves the source of the trigger when it reads the image.
- The squashed image shares no layer with its source image, so pushes and pulls cannot reuse layers that the registry or the host already has.
- The build history of the source image is not kept.

## Tests

The tests compare the output of `--print` with the expected files in `tests/fixtures/`, then squash each fixture and compare the image metadata. They start no container. See [tests/test.sh](tests/test.sh).

```shell
tests/test.sh
```

## Support this project

If you find this tool helpful, you can support its development via [PayPal](https://www.paypal.me/shinsenter).

Issues and pull requests are welcome. Pull requests must pass the tests before they are merged.

* * *

From Vietnam 🇻🇳 with love.
