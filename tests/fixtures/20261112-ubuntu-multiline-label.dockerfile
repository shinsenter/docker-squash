# PR #7: the Ubuntu image has a description label with line breaks,
# which broke the generated Dockerfile. Images based on Ubuntu, such as
# mcr.microsoft.com/dotnet/runtime, inherit this label.
# The digest pins ubuntu:26.04 so the expected output does not change.
FROM ubuntu:26.04@sha256:065aa8626841f16057b78b027b464cd59c4fac36c204c72dcbf48d66f5fa8a96
