# docker-squash
This simple shell script provides an alternative to [Docker's experimental `--squash` option](https://docs.docker.com/engine/reference/commandline/build/#squash) for building optimized Docker images by squashing layers.

## What is image squashing?
When Docker builds an image, it utilizes a layered filesystem (AUFS). Each command in the Dockerfile adds a new layer that contains only the changes from the previous layer. This makes builds very fast since only changed files have to be copied.

However, the layered filesystem also results in larger image sizes since each layer contains duplicate files. Squashing combines these layers into a single layer, reducing storage space and often improving runtime performance by decreasing mount points.

## Benefits over `docker build --squash`
The `--squash` option provided by Docker squashes all layers into one, reducing image size. However, it also discards all previous instructions like ENV, LABEL, etc.

This script also squashes image layers but keeps ENV, ARG, LABEL and other metadata from the original image.
- Retains user, workdir, and other runtime configurations
- Results in smaller image sizes by combining redundant layers
- Faster lookups at runtime by reducing layer mount points

In other words - smaller images but preserving more of the original image definition!

## Usage
```shell
./docker-squash.sh <source_image> [docker build options]
```

Where:
- `source_image` - The original image ID or `name:tag` to be squashed
- `docker build options` - Additional build options like `--build-arg`, `--label`, etc.

### Examples:
```sh
./docker-squash.sh myimage:latest
./docker-squash.sh myimage:latest -t myimage:squashed
./docker-squash.sh myimage:latest -t myimage:squashed --label "Squashed=true"
```

Output image tagging and docker build arguments are supported for advanced customization.

### More real-life examples
Squashing existing images or Dockerfiles is seamless while providing size and performance benefits.

#### Squash an existing image to reduce its size:
```sh
docker pull ubuntu:noble-20231214
./docker-squash.sh ubuntu:noble-20231214 -t ubuntu:noble-20231214-squashed
docker images | grep -F 'noble-20231214'
# Original image size: 93.1MB
# Squashed image size: 91.9MB
```

#### Specify target platform to squash multi-architecture images:
```sh
docker pull --platform linux/arm64 ubuntu:jammy
./docker-squash.sh ubuntu:jammy -t ubuntu:jammy-squashed --platform linux/arm64
docker images | grep -F 'jammy'
```

#### Inject pre-squash script which is executed before squashing:
You can add your shell script to a build argument named `PRESQUASH_SCRIPTS` and execute as root user. It may be useful to clean up the source image before squashing.
```sh
docker pull php:apache
./docker-squash.sh php:apache \
    --build-arg PRESQUASH_SCRIPTS='rm -rf /var/cache/* /var/lib/apt/lists/* /var/tmp/*' \
    -t php:apache-squashed
docker images | grep -F 'apache'
```

#### Inject label metadata which is retained after squashing:
```sh
docker pull php:apache
./docker-squash.sh php:apache -t php:apache-squashed --label squashed=true
docker images | grep -F 'apache'
```

#### Squash image built straight from a Dockerfile:
```sh
./docker-squash.sh /home/my-project/Dockerfile -t my-project:squashed
```

## Pros and Cons

### Pros
- Smaller image size
- Faster runtime performance
- Obfuscates build details
- Retains Dockerfile metadata

## Cons
- Slower rebuild time
- Can inhibit debugging capabilities
- Loss of Docker cache and remote build benefits

## Support this project
If you find this tool helpful and wish to support continued development, I welcome donations or other contributions:

### Donate
I appreciate monetary contributions via [PayPal](https://www.paypal.me/shinsenter) to help fund development costs. Your support is greatly appreciated.

### Contribute
This is open source software. If you have suggestions, spot issues, or can contribute code changes, please open GitHub issues or pull requests on this project repository. I welcome community input to help expand capabilities and fix problems!

Together we can build better tools for working with Docker. Thank you!

* * *

From Vietnam 🇻🇳 with love.
