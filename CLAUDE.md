# docker-squash

One POSIX shell script, `docker-squash.sh`, that squashes a Docker image into a single layer and restores its metadata. It reads the image config with `docker image inspect`, prints a Dockerfile with `jq`, and builds it.

## Principles

- Keep it simple. One script, `docker` and `jq` as the only dependencies. Prefer removing code over adding options.
- The script must run with `sh`, `bash` and `dash`. Use `printf '%s\n'` for image data, never `echo`: shells disagree on how `echo` treats backslashes (the cause of the revert of PR #6).
- All metadata comes from one jq program, `JQ_METADATA`. Add or fix an instruction there, one line per instruction. Values written inside double quotes go through `esc`.
- The generated Dockerfile declares no build argument other than `PRESQUASH_SCRIPTS` (the two `BUILDKIT_SBOM_SCAN_*` arguments are the only exception). Do not add new `ARG` instructions.
- The generated Dockerfile must pass `docker buildx build --check` without warnings.
- The usage text lives in the comment block at the top of the script, under the copyright block. `usage()` prints that block, so edit the comments to change the help.

## How the generated Dockerfile works

- The source image is copied with `COPY --link --from=<image> / /`, never used in `FROM`. `FROM` would run the `ONBUILD` triggers of the source image.
- `PRESQUASH_SCRIPTS` runs as root in a separate stage with the `ENV` values of the source image. An empty value selects the stage without the `RUN`, so images without a shell can be squashed.
- The default of `PRESQUASH_SCRIPTS` is `ENV PRESQUASH_SCRIPTS` of the source image when it is set, even to an empty value. The build argument replaces it because `ARG` comes after the `ENV` lines in the cleaning stage: keep that order.
- Without that `ENV`, the default deletes files but keeps the directories of `/var/cache` and `/var/log`. Deleting the directories breaks images such as nginx.
- A Dockerfile cannot hold a line break in a value. `esc` writes it as `\n`, and the script passes labels with line breaks as `--label` build options to keep their exact value.
- The script returns a non-zero exit code when the build fails.

## Tests

Run `tests/test.sh`. It prints one line per assertion and the totals, and writes the output of every command to `tests/logs/test.log`.

- Tests start no container. Assertions only read metadata with `docker image inspect`.
- A fixture starts `FROM scratch`, or from a real registry image pinned by digest (`image:tag@sha256:...`) so the expected output does not change. Prefer small images. To move a pin, change the digest, run `tests/test.sh --update` and review the diff.
- A fixture is a pair of files in `tests/fixtures/`: `<YYYYMMDD>-<name>.dockerfile` and `<YYYYMMDD>-<name>.out.txt`. The date is the day the fixture was created and the name is kebab-case.
- A fixture passes only when `docker-squash.sh <fixture>.dockerfile --print` prints exactly the instructions of the `.out.txt` file. Comment lines are ignored, so `.out.txt` files hold instructions only. The image name and image ID are replaced by `<image>` and `<id>`.
- Each fixture is also squashed for real, and the metadata of the squashed image must equal the metadata of the source image.
- Every bug fix and every new instruction needs a fixture, or a new case in an existing fixture, with a one-line comment that says what it covers.
- After changing the output of the script, run `tests/test.sh --update` and review the diff of the `.out.txt` files before committing.
- Fixtures are squashed with an empty `PRESQUASH_SCRIPTS`, because scratch and distroless images have no shell. The pre-squash step is tested separately with the nginx fixture.
- Run `docker buildx build --check` only on small outputs. With the output of the `full` fixture it crashed the Docker daemon twice (BuildKit 0.34.0, Docker 29.9.2, panic in `DockerfileLint`). The exact instruction that triggers the panic is not identified.

## CI

`.github/workflows/test.yml` runs `tests/test.sh` on an arm64 runner for pull requests and pushes to `main` that change `docker-squash.sh` or `tests/`. Other changes, such as docs or the workflow file itself, do not start the tests. Tests use arm64: create and update the expected outputs on arm64, because the metadata of a registry image can differ between platforms. A pull request is merged only when the `test` job passes.

## README

- Size numbers in the README must be measured, with the date and the Docker version. Do not estimate them.
- Use current official images in the examples, and keep one example that shows the saving from `PRESQUASH_SCRIPTS`.
- When the behavior of `PRESQUASH_SCRIPTS` or an option changes, update the README, the usage block in the script and this file together.

## Workflow

- Work on a `feature/...` branch. Never commit or push to `main`.
- Commit each group of related changes separately, for example script, tests, CI and docs.
- A commit message is one short line in Conventional Commits style: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`. No commit body and no `Co-authored-by` or other trailers.
