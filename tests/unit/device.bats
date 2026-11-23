#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
#
# Contract of device.jq: the checks that decide whether a block device may be
# written to. Each function takes one device object from
#
#   lsblk --json --bytes --output NAME,PATH,TYPE,RM,HOTPLUG,TRAN,SIZE,LABEL,MOUNTPOINTS
#
# and returns an array of objections. An empty array means "go ahead"; every
# objection is a phrase that completes the sentence "<device> ...".
#
# These guard destructive operations on machines that hold client data, so
# the refusals matter more than the acceptances.

readonly GIB=1073741824
readonly IMAGE_BYTES=$((1 * GIB))
readonly MIN_PERSISTENCE_BYTES=$((1 * GIB))
readonly ISO_LABEL=PANICOS
readonly PERSISTENCE_LABEL=panicos-persist
readonly LUKS_LABEL=persistence

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LIB_DIR="$REPO_ROOT/live/config/includes.chroot/usr/lib/panicos"
}

# device NAME TYPE RM HOTPLUG TRAN SIZE LABEL MOUNTPOINT [CHILD_JSON...]
# -> one lsblk-style device object. Pass "null" for an absent value.
device() {
  local -r name=$1 type=$2 rm=$3 hotplug=$4 tran=$5 size=$6 label=$7 mountpoint=$8
  shift 8
  local -r children="$(IFS=,; printf '%s' "$*")"
  jq --null-input --compact-output \
    --arg name "$name" --arg type "$type" \
    --argjson rm "$rm" --argjson hotplug "$hotplug" --argjson size "$size" \
    --argjson tran "$tran" --argjson label "$label" --argjson mountpoint "$mountpoint" \
    --argjson children "[$children]" \
    '{name: $name, path: "/dev/\($name)", type: $type, rm: $rm, hotplug: $hotplug,
      tran: $tran, size: $size, label: $label, mountpoints: [$mountpoint]}
     + (if ($children | length) > 0 then {children: $children} else {} end)'
}

blank_usb_stick() { device sdb disk true true '"usb"' $((32 * GIB)) null null; }

flashed_usb_stick() {
  device sdb disk true true '"usb"' $((32 * GIB)) "\"$ISO_LABEL\"" null \
    "$(device sdb1 part true true null "$IMAGE_BYTES" "\"$ISO_LABEL\"" null)" \
    "$(device sdb2 part true true null 5242880 '"ESP"' null)"
}

flash_objections() {
  jq --raw-output -L "$LIB_DIR" \
    --argjson image_bytes "$IMAGE_BYTES" \
    --argjson min_persistence_bytes "$MIN_PERSISTENCE_BYTES" \
    'include "device"; flash_objections($image_bytes; $min_persistence_bytes)[]'
}

persist_objections() {
  jq --raw-output -L "$LIB_DIR" \
    --arg iso_label "$ISO_LABEL" \
    --argjson persistence_labels "[\"$PERSISTENCE_LABEL\", \"$LUKS_LABEL\"]" \
    'include "device"; persist_objections($iso_label; $persistence_labels)[]'
}

# --- flash -------------------------------------------------------------------

@test "flash: a blank USB stick is accepted" {
  run flash_objections <<< "$(blank_usb_stick)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "flash: a stick that reports hotplug but not removable is accepted" {
  run flash_objections <<< "$(device sdb disk false true '"usb"' $((32 * GIB)) null null)"
  [ -z "$output" ]
}

@test "flash: an internal SATA disk is refused" {
  run flash_objections <<< "$(device sda disk false false '"sata"' $((500 * GIB)) null null)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not a removable device"* ]]
}

@test "flash: an internal NVMe disk is refused" {
  run flash_objections <<< "$(device nvme0n1 disk false false '"nvme"' $((500 * GIB)) null null)"
  [[ "$output" == *"not a removable device"* ]]
}

@test "flash: a partition is refused" {
  run flash_objections <<< "$(device sdb1 part true true null $((32 * GIB)) null null)"
  [[ "$output" == *"not a whole disk"* ]]
}

@test "flash: a stick with a mounted partition is refused, naming the mount point" {
  run flash_objections <<< "$(device sdb disk true true '"usb"' $((32 * GIB)) null null \
    "$(device sdb1 part true true null $((32 * GIB)) '"DATA"' '"/media/operator/DATA"')")"
  [[ "$output" == *"/media/operator/DATA"* ]]
}

@test "flash: a stick too small for the image plus persistence is refused" {
  run flash_objections <<< "$(device sdb disk true true '"usb"' $((IMAGE_BYTES + MIN_PERSISTENCE_BYTES - 1)) null null)"
  [[ "$output" == *"too small"* ]]
}

@test "flash: a stick of exactly the minimum size is accepted" {
  run flash_objections <<< "$(device sdb disk true true '"usb"' $((IMAGE_BYTES + MIN_PERSISTENCE_BYTES)) null null)"
  [ -z "$output" ]
}

@test "flash: every objection is reported, one per line" {
  run flash_objections <<< "$(device sda1 part false false null 1024 null '"/"')"
  [ "${#lines[@]}" -eq 4 ]
}

# --- persist -----------------------------------------------------------------

@test "persist: a freshly flashed stick is accepted" {
  run persist_objections <<< "$(flashed_usb_stick)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "persist: a disk without a PanicOS image is refused" {
  run persist_objections <<< "$(device sda disk false false '"sata"' $((500 * GIB)) null null \
    "$(device sda1 part false false null $((500 * GIB)) '"Windows"' null)")"
  [[ "$output" == *"does not carry a PanicOS image"* ]]
}

@test "persist: a stick that already has a persistence volume is refused" {
  run persist_objections <<< "$(device sdb disk true true '"usb"' $((32 * GIB)) "\"$ISO_LABEL\"" null \
    "$(device sdb1 part true true null "$IMAGE_BYTES" "\"$ISO_LABEL\"" null)" \
    "$(device sdb3 part true true null $((30 * GIB)) "\"$PERSISTENCE_LABEL\"" null)")"
  [[ "$output" == *"already has a persistence volume"* ]]
}

@test "persist: a stick with an encrypted persistence volume is refused" {
  run persist_objections <<< "$(device sdb disk true true '"usb"' $((32 * GIB)) "\"$ISO_LABEL\"" null \
    "$(device sdb1 part true true null "$IMAGE_BYTES" "\"$ISO_LABEL\"" null)" \
    "$(device sdb3 part true true null $((30 * GIB)) "\"$LUKS_LABEL\"" null)")"
  [[ "$output" == *"already has a persistence volume"* ]]
}

@test "persist: a partition is refused" {
  run persist_objections <<< "$(device sdb1 part true true null "$IMAGE_BYTES" "\"$ISO_LABEL\"" null)"
  [[ "$output" == *"not a whole disk"* ]]
}

@test "persist: a stick with a mounted partition is refused" {
  run persist_objections <<< "$(device sdb disk true true '"usb"' $((32 * GIB)) "\"$ISO_LABEL\"" null \
    "$(device sdb1 part true true null "$IMAGE_BYTES" "\"$ISO_LABEL\"" '"/mnt/iso"')")"
  [[ "$output" == *"/mnt/iso"* ]]
}

# --- where the persistence partition goes ------------------------------------
#
# Input: `sfdisk --json DEVICE`. The persistence partition starts at the first
# 1 MiB boundary at or after the end of the last existing partition.

readonly ISO_END_SECTOR=671744   # 64 + 671680, the layout of a real PanicOS ISO

# partition_table SECTOR_SIZE START:SIZE... -> sfdisk-style JSON
partition_table() {
  local -r sector_size=$1
  shift
  printf '%s\n' "$@" | jq --raw-input --slurp --argjson sectorsize "$sector_size" \
    '{partitiontable: {label: "dos", unit: "sectors", sectorsize: $sectorsize,
       partitions: [split("\n")[] | select(. != "") | split(":")
                    | {start: (.[0] | tonumber), size: (.[1] | tonumber)}]}}'
}

panicos_iso_table() { partition_table 512 64:671680 540:6656; }

append_start_sector() {
  jq -L "$LIB_DIR" 'include "device"; append_start_sector'
}

space_objections() {
  local -r disk_bytes=$1
  jq --raw-output -L "$LIB_DIR" \
    --argjson disk_bytes "$disk_bytes" \
    --argjson min_persistence_bytes "$MIN_PERSISTENCE_BYTES" \
    'include "device"; space_objections($disk_bytes; $min_persistence_bytes)[]'
}

@test "append: starts right after the ISO when its end is already aligned" {
  run append_start_sector <<< "$(panicos_iso_table)"
  [ "$status" -eq 0 ]
  [ "$output" -eq "$ISO_END_SECTOR" ]
}

@test "append: the overlapping EFI partition inside the ISO does not matter" {
  run append_start_sector <<< "$(partition_table 512 540:6656 64:671680)"
  [ "$output" -eq "$ISO_END_SECTOR" ]
}

@test "append: rounds up to the next 1 MiB boundary" {
  run append_start_sector <<< "$(partition_table 512 64:671681)"
  [ "$output" -eq $((ISO_END_SECTOR + 2048)) ]
}

@test "append: 1 MiB alignment follows the sector size" {
  run append_start_sector <<< "$(partition_table 4096 8:100)"
  [ "$output" -eq 256 ]
}

@test "space: enough room after the image is accepted" {
  run space_objections $((ISO_END_SECTOR * 512 + MIN_PERSISTENCE_BYTES)) <<< "$(panicos_iso_table)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "space: one byte short of the minimum is refused" {
  run space_objections $((ISO_END_SECTOR * 512 + MIN_PERSISTENCE_BYTES - 1)) <<< "$(panicos_iso_table)"
  [[ "$output" == *"free after the image"* ]]
}

@test "space: a device with no partitions is refused" {
  run space_objections $((32 * GIB)) <<< "$(partition_table 512)"
  [[ "$output" == *"no partitions"* ]]
}

# --- facts lsblk cannot be trusted for ---------------------------------------
#
# lsblk takes labels from the udev database, which is absent in a container
# and can lag behind a write. Callers probe the device instead and merge the
# result in with with_labels, keyed by device path.

with_labels() {
  local -r label_by_path=$1
  jq --compact-output -L "$LIB_DIR" --argjson label_by_path "$label_by_path" \
    'include "device"; with_labels($label_by_path) | [nodes | .label]'
}

@test "labels: probed labels replace lsblk's, on the device and its partitions" {
  run with_labels '{"/dev/sdb": "PANICOS", "/dev/sdb1": "PANICOS"}' \
    <<< "$(device sdb disk true true '"usb"' $((32 * GIB)) null null \
      "$(device sdb1 part true true null "$IMAGE_BYTES" '"stale"' null)")"
  [ "$status" -eq 0 ]
  [ "$output" = '["PANICOS","PANICOS"]' ]
}

@test "labels: a node that was probed and has no label ends up with none" {
  run with_labels '{"/dev/sdb": null}' \
    <<< "$(device sdb disk true true '"usb"' $((32 * GIB)) '"stale"' null)"
  [ "$output" = '[null]' ]
}

@test "persist: a loop device counts as a whole disk" {
  run persist_objections <<< "$(device loop0 loop false false null $((4 * GIB)) "\"$ISO_LABEL\"" null)"
  [ -z "$output" ]
}

@test "flash: a loop device is refused as not removable" {
  run flash_objections <<< "$(device loop0 loop false false null $((32 * GIB)) null null)"
  [ "$output" = "is not a removable device" ]
}
