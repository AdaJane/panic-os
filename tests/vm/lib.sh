# shellcheck shell=bash
# SPDX-License-Identifier: MIT
# shellcheck disable=SC2034  # a library: its constants are used by the tests that source it
#
# lib.sh — shared by the VM tests: describing a machine, booting it in QEMU,
# and reading what the guest reported on its serial port.
#
# A machine is a list of QEMU arguments, composed from the *_args functions
# (each prints one argument per line):
#
#   mapfile -t machine < <(usb_stick_args ...; firmware_args ...)
#   boot "$serial_log" "${machine[@]}" && serial_has "$serial_log" "..."
#
# Each boot goes through the real bootloader. The guest's self-test is
# triggered by a systemd credential passed over SMBIOS, so the boot path under
# test is exactly the one an operator gets. Protocol: see constants.sh.

VM_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VM_LIB_DIR
readonly REPO_ROOT="$VM_LIB_DIR/../.."
readonly IMAGE_ROOT="$REPO_ROOT/live/config/includes.chroot"
# shellcheck source=live/config/includes.chroot/usr/lib/panicos/constants.sh
source "$IMAGE_ROOT/usr/lib/panicos/constants.sh"

readonly SCENARIOS="$VM_LIB_DIR/scenarios.tsv"
readonly OVMF_DIR=/usr/share/OVMF
readonly NO_FIRMWARE_FILE=-
readonly GUEST_MEMORY_MB=2048
readonly GUEST_CPUS=2
readonly BOOT_TIMEOUT_SECONDS=600

# Values for usb_stick_args.
readonly READ_ONLY=on
readonly WRITABLE=off
readonly REMOVABLE=on
readonly FIXED=off

readonly EX_USAGE=64
readonly EX_NOINPUT=66
readonly EX_UNAVAILABLE=69

# require_iso_and_kvm ISO -> exits unless the test can run at all.
require_iso_and_kvm() {
  local -r iso=$1
  [[ -r $iso ]] || {
    printf 'cannot read ISO: %s\n' "$iso" >&2
    exit "$EX_NOINPUT"
  }
  [[ -w /dev/kvm ]] || {
    printf '/dev/kvm is not available\n' >&2
    exit "$EX_UNAVAILABLE"
  }
}

# usb_stick_args FILE READ_ONLY|WRITABLE REMOVABLE|FIXED -> the boot stick.
# FIXED is how many USB SSDs and some fast sticks present themselves.
usb_stick_args() {
  local -r file=$1 read_only=$2 removable=$3
  printf '%s\n' \
    -device qemu-xhci \
    -drive "if=none,id=stick,format=raw,readonly=$read_only,file=$file" \
    -device "usb-storage,drive=stick,removable=$removable,bootindex=0"
}

# internal_disk_args FILE -> a writable SATA disk, standing in for the disk of
# the machine being recovered.
internal_disk_args() {
  local -r file=$1
  printf '%s\n' \
    -drive "if=none,id=internal,format=raw,file=$file" \
    -device ide-hd,drive=internal,bus=ide.0
}

# firmware_args OVMF_CODE OVMF_VARS SECUREBOOT VARS_COPY -> the firmware.
# SeaBIOS needs no arguments.
firmware_args() {
  local -r code=$1 vars=$2 secureboot=$3 vars_copy=$4
  [[ $code != "$NO_FIRMWARE_FILE" ]] || return 0
  # OVMF writes to its variable store, so each machine gets a private copy.
  cp "$OVMF_DIR/$vars" "$vars_copy"
  printf '%s\n' \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_DIR/$code" \
    -drive "if=pflash,format=raw,unit=1,file=$vars_copy"
  # Secure Boot firmware keeps its variables in SMM-protected flash.
  [[ $secureboot != 1 ]] || printf '%s\n' \
    -machine smm=on \
    -global driver=cfi.pflash01,property=secure,value=on
}

# boot SERIAL_LOG QEMU_ARG... -> runs the machine until the guest powers off.
boot() {
  local -r serial_log=$1
  shift
  timeout "$BOOT_TIMEOUT_SECONDS" qemu-system-x86_64 \
    -machine q35 -accel kvm -cpu host \
    -m "$GUEST_MEMORY_MB" -smp "$GUEST_CPUS" \
    -display none -nic none -no-reboot \
    -serial "file:$serial_log" \
    -smbios "type=11,value=io.systemd.credential:$PANICOS_SELFTEST_CREDENTIAL=1" \
    "$@"
}

# serial_has SERIAL_LOG LINE... -> succeeds if the log contains every line.
serial_has() {
  local -r serial_log=$1
  shift
  local expected
  for expected in "$@"; do
    grep --quiet --fixed-strings "$expected" "$serial_log" || return 1
  done
}

# report NAME STATUS [LOG...] -> a TAP line; on failure, the logs on stderr.
# Returns STATUS.
report() {
  local -r name=$1 status=$2
  shift 2
  if [[ $status -eq 0 ]]; then
    printf 'ok - %s\n' "$name"
    return 0
  fi
  printf 'not ok - %s\n' "$name"
  local log
  for log in "$@"; do
    printf '# %s\n' "$log"
    sed 's/^/#   /' "$log" 2> /dev/null || true
  done >&2
  return 1
}

# for_each_scenario FUNCTION ARG... -> calls FUNCTION ARG... NAME FIRMWARE
# SECUREBOOT OVMF_CODE OVMF_VARS for every row of scenarios.tsv. Fails if any
# call failed, after running them all.
for_each_scenario() {
  local name firmware secureboot code vars
  local failed=0
  while IFS=$'\t' read -r name firmware secureboot code vars; do
    "$@" "$name" "$firmware" "$secureboot" "$code" "$vars" || failed=1
  done < <(grep --invert-match --extended-regexp '^(#|$)' "$SCENARIOS")
  return "$failed"
}
