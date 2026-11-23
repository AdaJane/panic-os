# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# device.sh — what panicos-flash and panicos-persist share: gathering the
# facts about a block device that device.jq judges, and refusing loudly.
#
# Source it after constants.sh, with PROGRAM (the caller's name, for
# messages) and LIB_DIR (the directory holding device.jq) set.

readonly LSBLK_COLUMNS=NAME,PATH,TYPE,RM,HOTPLUG,TRAN,SIZE,LABEL,MOUNTPOINTS
# blkid(8): "2: the specified tokens were not found".
readonly BLKID_NOTHING_FOUND=2
readonly BLOCK_DEVICE_TIMEOUT_SECONDS=10

die() {
  printf '%s: %s\n' "$PROGRAM" "$*" >&2
  exit 1
}

# quietly COMMAND... -> runs it; its output is shown only if it fails.
quietly() {
  local output
  if ! output="$("$@" 2>&1)"; then
    printf '%s\n' "$output" >&2
    die "failed: $*"
  fi
}

# device_jq JQ_ARG... -> jq with device.jq on its library path.
device_jq() {
  jq --raw-output -L "$LIB_DIR" "$@"
}

# wait_for_block_device NODE -> returns once NODE exists. The kernel
# announces new partitions asynchronously.
wait_for_block_device() {
  local -r node=$1
  timeout "$BLOCK_DEVICE_TIMEOUT_SECONDS" \
    bash -c 'until [[ -b $0 ]]; do sleep 0.1; done' "$node" \
    || die "the kernel did not create $node"
}

# probed_label NODE -> its volume label, read from the device itself; empty
# if it has none.
probed_label() {
  local -r node=$1
  blkid --probe --match-tag LABEL --output value "$node" \
    || [[ $? -eq $BLKID_NOTHING_FOUND ]] \
    || die "cannot probe $node"
}

# probed_labels DEVICE -> JSON object: path of DEVICE and of each of its
# partitions -> label, or null.
probed_labels() {
  local -r device=$1
  local node
  lsblk --list --noheadings --output PATH "$device" \
    | while read -r node; do
      jq --null-input --arg path "$node" --arg label "$(probed_label "$node")" \
        '{($path): (if $label == "" then null else $label end)}'
    done \
    | jq --slurp 'add'
}

# device_facts DEVICE -> the JSON object device.jq's *_objections functions
# take: lsblk's description of DEVICE, with labels probed from the device
# itself (lsblk's own come from the udev database, which is absent in a
# container and can lag behind a write).
device_facts() {
  local -r device=$1
  lsblk --json --bytes --output "$LSBLK_COLUMNS" "$device" \
    | device_jq --compact-output --argjson label_by_path "$(probed_labels "$device")" \
      'include "device"; .blockdevices[0] | with_labels($label_by_path)'
}

# in_use_objection DEVICE -> a line if the kernel has DEVICE or one of its
# partitions mounted or held open. Unlike lsblk's mount points, this sees
# mounts in every namespace, so it also holds inside a container.
in_use_objection() {
  local -r device=$1
  blockdev --rereadpt "$device" 2> /dev/null \
    || printf 'is in use: a partition is mounted or held open\n'
}

# refuse_if DEVICE OBJECTIONS -> exits, listing them, unless there are none.
refuse_if() {
  local -r device=$1 objections=$2
  [[ -n $objections ]] || return 0
  local objection
  while IFS= read -r objection; do
    printf '%s: %s %s\n' "$PROGRAM" "$device" "$objection"
  done <<< "$objections" >&2
  exit 1
}
