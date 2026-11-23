# SPDX-License-Identifier: MIT
# device.jq — decide whether a block device may be written to.
#
# These checks stand between an operator's typo and a client's disk, so they
# are pure functions over data and are unit-tested (tests/unit/device.bats).
#
# Every *_objections function returns an array of objections. Empty means the
# operation may proceed. Each objection is a phrase completing the sentence
# "<device> ...". All objections are returned, not just the first, so the
# operator sees the whole picture. Each rule reads "(when this holds | say this)".

# --- Is this the right device? -----------------------------------------------
#
# Input to the functions below: one device object as printed by
#
#   lsblk --json --bytes --output NAME,PATH,TYPE,RM,HOTPLUG,TRAN,SIZE,LABEL,MOUNTPOINTS
#
# (an element of .blockdevices, with its partitions under .children).

# lsblk TYPE values that denote a whole device rather than a part of one.
# "loop" is an image file attached with losetup.
def WHOLE_DEVICE_TYPES: ["disk", "loop"];
def TRANSPORT_USB: "usb";

# The device itself and everything on it.
def nodes: recurse(.children[]?);

# Replace every node's label with the one probed for its path. lsblk reads
# labels from the udev database, which is missing in a container and can lag
# behind a write; callers probe the device itself (blkid --probe) instead.
def with_labels($label_by_path):
  .label = $label_by_path[.path]
  | if has("children")
    then .children |= map(with_labels($label_by_path))
    else .
    end;

def mountpoints: [nodes | .mountpoints[]? | values];

def has_label($label): any(nodes; .label == $label);

def is_removable: .rm == true or .hotplug == true or .tran == TRANSPORT_USB;

def not_whole_disk_objection:
  select(.type as $type | WHOLE_DEVICE_TYPES | index($type) | not)
  | "is not a whole disk (it is a \(.type))";

def mounted_objections:
  mountpoints[] | "has a filesystem mounted at \(.)";

# May the PanicOS image be written over this device?
def flash_objections($image_bytes; $min_persistence_bytes):
  [ not_whole_disk_objection,
    (select(is_removable | not)
     | "is not a removable device"),
    mounted_objections,
    (select(.size < $image_bytes + $min_persistence_bytes)
     | "is too small: \(.size) bytes, need \($image_bytes + $min_persistence_bytes)")
  ];

# May a persistence partition be added to this device?
# $persistence_labels lists every label that marks a persistence volume: the
# filesystem's, and the LUKS header's when the volume is encrypted.
def persist_objections($iso_label; $persistence_labels):
  [ not_whole_disk_objection,
    mounted_objections,
    (select(has_label($iso_label) | not)
     | "does not carry a PanicOS image (no volume labelled \($iso_label))"),
    (select(any($persistence_labels[] as $label | has_label($label); .))
     | "already has a persistence volume")
  ];

# --- Where the persistence partition goes ------------------------------------
#
# Input to the functions below: the output of `sfdisk --json DEVICE`.

def BYTES_PER_MIB: 1048576;

def partitions: .partitiontable.partitions // [];

def sector_bytes: .partitiontable.sectorsize;

# First sector past every existing partition. A PanicOS ISO's partitions
# overlap (the EFI partition lies inside the ISO one), hence max, not last.
def end_sector: [partitions[] | .start + .size] | max;

# The first 1 MiB boundary at or after the end of the last partition.
def append_start_sector:
  (BYTES_PER_MIB / sector_bytes) as $alignment
  | ((end_sector + $alignment - 1) / $alignment | floor) * $alignment;

# Is there room for a persistence partition on a device of $disk_bytes?
def space_objections($disk_bytes; $min_persistence_bytes):
  if (partitions | length) == 0 then
    ["has no partitions, so it was not written from a PanicOS image"]
  else
    ($disk_bytes - append_start_sector * sector_bytes) as $free_bytes
    | [ select($free_bytes < $min_persistence_bytes)
        | "has \($free_bytes) bytes free after the image, need \($min_persistence_bytes)" ]
  end;
