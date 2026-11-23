# SPDX-License-Identifier: MIT
# PanicOS build entry points.
#
# Everything runs inside the pinned build container (build/Dockerfile); the
# host needs only Docker and make.
#
#   make iso                     build out/panicos-<version>-amd64.iso
#   make test-unit               bats unit tests
#   make test-vm                 boot the ISO in QEMU: BIOS, UEFI, Secure Boot;
#                                persistence; client-disk safety
#   make lint                    shellcheck
#   make test                    lint, test-unit and test-vm
#   make flash DEVICE=/dev/sdX   ERASE a USB stick and write the ISO to it,
#                                with an encrypted persistence volume
#                                (ENCRYPT=no for an unencrypted one)
#   make persist DEVICE=/dev/sdX add a persistence volume to a stick that was
#                                written with another tool
#   make clean                   remove out/ and the build cache volume

SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
.DELETE_ON_ERROR:

IMAGE        := panicos-build
CACHE_VOLUME := panicos-build-cache
WORK_DIR     := /build

VERSION := $(shell date -u +%Y.%m.%d)-$(shell git describe --tags --always --dirty 2>/dev/null || echo uncommitted)
ISO     ?= out/panicos-$(VERSION)-amd64.iso
# Where this checkout is published, as an https URL, or empty if it has no
# remote yet. Recorded in the image so that bug reports about a build go to
# whoever built it, a fork included, and not to Debian.
HOME_URL := $(shell git config --get remote.origin.url 2>/dev/null | sed -E 's|^git@([^:]+):|https://\1/|; s|^ssh://git@|https://|; s|\.git$$||')

HOST_UID := $(shell id -u)
HOST_GID := $(shell id -g)

SHELL_SOURCES := \
	scripts/gen-package-list \
	scripts/gen-boot-menu \
	scripts/build-iso \
	tests/vm/lib.sh \
	tests/vm/boot-test \
	tests/vm/persistence-test \
	tests/vm/safety-test \
	live/auto/config \
	live/config/hooks/normal/0100-enable-panicos-units.hook.chroot \
	live/config/hooks/normal/0200-disable-lvm-autoactivation.hook.chroot \
	live/config/hooks/normal/0300-os-release.hook.chroot \
	live/config/hooks/normal/0400-claude-code-on-request.hook.chroot \
	live/config/hooks/normal/8040-remove-mdadm-configuration.hook.chroot \
	live/config/includes.chroot/usr/lib/live/boot/9995-panicos-strict-medium.sh \
	live/config/includes.chroot/usr/bin/panicos-claude-offer \
	live/config/includes.chroot/usr/bin/panicos-flash \
	live/config/includes.chroot/usr/bin/panicos-install-claude \
	live/config/includes.chroot/usr/bin/panicos-persist \
	live/config/includes.chroot/usr/bin/panicos-selftest \
	live/config/includes.chroot/usr/bin/panicos-status \
	live/config/includes.chroot/usr/lib/panicos/claude.sh \
	live/config/includes.chroot/usr/lib/panicos/constants.sh \
	live/config/includes.chroot/usr/lib/panicos/device.sh \
	live/config/includes.chroot/usr/lib/panicos/persistence.sh \
	live/config/includes.chroot/usr/lib/panicos/selftest-report

docker_run       = docker run --rm --volume $(CURDIR):/src --workdir /src
# Unprivileged, as the invoking user: lint and unit tests touch nothing.
run_as_user      = $(docker_run) --user $(HOST_UID):$(HOST_GID) $(IMAGE)
# live-build mounts /proc, /sys and /dev/pts inside its chroot, which Docker
# only permits in a privileged container.
run_privileged   = $(docker_run) --privileged \
	--volume $(CACHE_VOLUME):$(WORK_DIR) \
	--env PANICOS_WORK=$(WORK_DIR) \
	--env PANICOS_VERSION=$(VERSION) \
	--env PANICOS_HOME_URL=$(HOME_URL) \
	--env HOST_UID=$(HOST_UID) --env HOST_GID=$(HOST_GID) \
	$(IMAGE)
run_with_kvm     = $(docker_run) --device /dev/kvm $(IMAGE)
# The persistence and safety tests attach disk images as loop devices and
# partition them, and flashing writes to a real one: all need the host's /dev.
run_with_devices = $(docker_run) --privileged --volume /dev:/dev $(IMAGE)
# Flashing asks for confirmation and a passphrase, so it needs a terminal.
run_interactive  = $(docker_run) --interactive --tty --privileged --volume /dev:/dev $(IMAGE)

IMAGE_BIN        := live/config/includes.chroot/usr/bin
ENCRYPT          ?= yes
PERSIST_OPTIONS  := $(if $(filter no,$(ENCRYPT)),--no-encrypt)
require_device    = $(if $(DEVICE),,$(error DEVICE is required, for example: make $@ DEVICE=/dev/sdX))

.PHONY: container lint test-unit iso test-vm test flash persist clean

container:
	docker build --quiet --tag $(IMAGE) build/ >/dev/null

lint: container
	$(run_as_user) shellcheck $(SHELL_SOURCES)

test-unit: container
	$(run_as_user) bats tests/unit

iso: container
	$(run_privileged) scripts/build-iso

test-vm: container
	$(run_with_kvm) tests/vm/boot-test $(ISO)
	$(run_with_devices) tests/vm/persistence-test $(ISO)
	$(run_with_devices) tests/vm/safety-test $(ISO)

test: lint test-unit test-vm

flash: container
	$(require_device)
	$(run_interactive) $(IMAGE_BIN)/panicos-flash $(PERSIST_OPTIONS) $(ISO) $(DEVICE)

persist: container
	$(require_device)
	$(run_interactive) $(IMAGE_BIN)/panicos-persist $(PERSIST_OPTIONS) $(DEVICE)

clean:
	rm -rf out
	docker volume rm --force $(CACHE_VOLUME) >/dev/null
