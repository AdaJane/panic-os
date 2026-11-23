# SPDX-License-Identifier: MIT
# Build and test environment for PanicOS.
#
# Debian's live-build must run on Debian: Ubuntu and Mint ship an old fork under
# the same package name. The base image is pinned by digest so the toolchain
# only changes when this line does.
FROM debian:trixie@sha256:9c6e381421d0f48d1b8133e573f33c185ee16cbf505eda9c4a8a4791b25ea8a6

ENV DEBIAN_FRONTEND=noninteractive

# One package per line, sorted, so diffs stay readable.
#   live-build .. xorriso   build the ISO
#   cryptsetup-bin .. parted  create the persistence partition in tests
#   ovmf, qemu-*            boot the result under BIOS and UEFI
#   bats, shellcheck        unit tests and lint
RUN apt-get update \
 && apt-get install --yes --no-install-recommends \
      bats \
      ca-certificates \
      cryptsetup-bin \
      debootstrap \
      dosfstools \
      e2fsprogs \
      fdisk \
      gpg \
      jq \
      live-build \
      make \
      mtools \
      ovmf \
      parted \
      qemu-system-x86 \
      qemu-utils \
      shellcheck \
      squashfs-tools \
      xorriso \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
