# Design — `partitions_by_size` + `mount_partitions`

**Date:** 2026-07-02
**Branch:** `feat/audit-fixes-veracrypt-parallel` (existing — same branch as the audit/veracrypt work)

## Goals

Two new small, independent helper functions in `zsh-useful-functions.zsh`:

1. **`partitions_by_size <min> <max>`** — list partitions whose size falls in the
   inclusive range `[min, max]`.
2. **`mount_partitions [-b <base>] <device>...`** — mount each device under a base
   directory (default `/mnt`), creating a subdirectory named after the device.

Both pair with the existing disk/crypto helpers (`open-partitions` unlocks but does
not mount; `mount_partitions` mounts; `partitions_by_size` helps find devices).

## Constraints (project-wide)

- Target shell **zsh**; zsh idioms (`${var:t}`, `zparseopts`, `local -r`, glob
  qualifiers). Preserve existing style: usage banner on `argc == 0`/invalid input,
  `[ ]` POSIX tests, explicit `unset` of loop vars, explicit non-zero `return`.
- **No new external tool dependencies.** `lsblk` (util-linux), `numfmt` (coreutils),
  `mount` (util-linux) are all already assumed present (`mount --mkdir` is already
  used by `open_mount_veracrypt`). **`jq` is deliberately NOT used** — filtering is
  done in zsh.
- **TDD** via bats. Both functions have pure, testable logic once the external
  command (`lsblk` / `mount`) is stubbed, so they are fully unit-testable — they are
  NOT destructive/hardware exceptions. Tests stub `lsblk`/`mount`; `numfmt` runs for
  real (coreutils).
- Runner: `./test/bats/bin/bats test/`.

## Function 1 — `partitions_by_size`

**Interface:** `partitions_by_size <min-size> <max-size>`
- Sizes accept IEC suffixes (`K M G T`, base 1024) or raw bytes, converted with
  `numfmt --from=iec`. Example: `partitions_by_size 1G 2G`.
- Prints every partition whose size is in `[min, max]` (**both inclusive**), one per
  line, as `NAME<TAB>SIZE_bytes` (e.g. `nvme1n1p4\t1073741824`).

**Behavior:**
- `$# != 2` → usage banner, `return 1`.
- Convert `min`/`max` via `numfmt --from=iec "$1"` (stderr suppressed). If either
  conversion yields empty (invalid) → `Error: invalid size ...` to stderr, `return 1`.
- If `min > max` → `Error: min-size must be <= max-size` to stderr, `return 1`.
- Enumerate with `lsblk -b -l -n -o NAME,SIZE,TYPE`:
  - `-b` bytes, `-l` list mode (no tree-drawing chars in NAME), `-n` no header.
  - For each row, keep it iff `type == "part"` and `min <= size <= max`; print
    `NAME<TAB>SIZE`.
- `unset` loop vars.

**Reference implementation:**
```zsh
# List partitions whose size is within [min, max] (inclusive).
# Sizes accept IEC suffixes (K/M/G/T, base 1024) or raw bytes.
partitions_by_size(){
    if [ "$#" -ne 2 ];
    then
        echo "Usage: partitions_by_size <min-size> <max-size>"
        echo "  Sizes accept IEC suffixes: K M G T (e.g. 500M, 1G, 2T), or raw bytes."
        echo "  Prints NAME<TAB>SIZE for partitions with min <= size <= max."
        echo "Example: partitions_by_size 1G 2G"
        return 1
    fi

    local min max
    min=$(numfmt --from=iec "$1" 2>/dev/null)
    max=$(numfmt --from=iec "$2" 2>/dev/null)

    if [ -z "$min" ] || [ -z "$max" ];
    then
        echo "Error: invalid size (use IEC suffixes like 500M, 1G, 2T, or bytes)" >&2
        return 1
    fi

    if [ "$min" -gt "$max" ];
    then
        echo "Error: min-size must be <= max-size" >&2
        return 1
    fi

    local name size type
    while read -r name size type;
    do
        if [ "$type" = "part" ] && [ "$size" -ge "$min" ] && [ "$size" -le "$max" ];
        then
            printf '%s\t%s\n' "$name" "$size"
        fi
    done < <(lsblk -b -l -n -o NAME,SIZE,TYPE)
    unset name size type
}
```

**Tests (stub `lsblk`; real `numfmt`):**
- `$# != 2` (0/1/3 args) → usage, status 1.
- invalid size (`partitions_by_size zzz 2G`) → "invalid size", status 1.
- `min > max` (`partitions_by_size 3G 1G`) → "min-size must be <= max-size", status 1.
- filtering: stub lsblk emits a mix (a disk, parts of 512M/1G/2G/5G); `1G 2G` prints
  exactly the 1G and 2G parts (with sizes), excludes the disk and the 512M/5G parts.
- inclusive borders: a part of exactly `2G` is included when `max == 2G`; a part of
  exactly `1G` included when `min == 1G`.

## Function 2 — `mount_partitions`

**Interface:** `mount_partitions [-b <base> | --base <base>] <device>...`
- Mounts each `<device>` at `<base>/<device-basename>` (`${dev:t}`), creating the
  directory. Base defaults to `/mnt`.
- Example: `mount_partitions /dev/mapper/veracrypt1 /dev/mapper/veracrypt2` →
  `/mnt/veracrypt1`, `/mnt/veracrypt2`. `mount_partitions -b /media /dev/sda1` →
  `/media/sda1`.

**Behavior:**
- Parse `-b`/`--base` with `zparseopts -D -E -F`. Invalid flag → `Error: invalid
  option` to stderr, `return 1`.
- `-h`/`--help` or `argc == 0` → usage banner (`return 0` for help, else `1`).
- `base = ${o_base[2]:-/mnt}`.
- For each device: `mount --mkdir "$dev" "$base/${dev:t}"`; on failure print
  `Error: failed to mount <dev> at <target>` to stderr and `return 1` (stop at first
  failure, consistent with `open-partitions` sequential mode).
- `unset` loop vars.

**Reference implementation:**
```zsh
# Mount one or more devices under a base directory (default /mnt), creating a
# subdirectory named after each device's basename.
mount_partitions(){
    local -a o_base o_help
    zparseopts -D -E -F -- b:=o_base -base:=o_base h=o_help -help=o_help 2>/dev/null
    local -r parse_rc=$?

    if [ "$parse_rc" -ne "0" ];
    then
        echo "Error: invalid option" >&2
        return 1
    fi

    if [ -n "$o_help" ] || [ "$#" -eq "0" ];
    then
        echo "Usage: mount_partitions [-b <base-dir>] <device>..."
        echo "  Mounts each <device> at <base-dir>/<device-basename>, creating the dir."
        echo "  -b, --base   base mount directory (default: /mnt)"
        echo "Example: mount_partitions /dev/mapper/veracrypt1 /dev/mapper/veracrypt2"
        echo "Example: mount_partitions -b /media /dev/sda1"
        [ -n "$o_help" ] && return 0
        return 1
    fi

    local -r base="${o_base[2]:-/mnt}"

    local i target
    for i in "$@"
    do
        target="$base/${i:t}"
        if ! mount --mkdir "$i" "$target";
        then
            echo "Error: failed to mount $i at $target" >&2
            unset i target
            return 1
        fi
    done
    unset i target
}
```

**Tests (stub `mount` to echo `MNT:$*`):**
- `argc == 0` → usage, status 1. `-h` → usage, status 0.
- default base: `mount_partitions /dev/mapper/veracrypt1` →
  `MNT:--mkdir /dev/mapper/veracrypt1 /mnt/veracrypt1`, status 0.
- custom base: `mount_partitions -b /media /dev/sda1` →
  `MNT:--mkdir /dev/sda1 /media/sda1`.
- multiple devices: both targets appear, basenames derived from the device path.
- failure: stub `mount` returns 1 → "failed to mount", status 1.
- invalid flag: `mount_partitions -x /dev/sda1` → "invalid option", status 1.

## Placement & files

- `zsh-useful-functions.zsh`: add both functions after `iommu_groups` (disk/hardware
  neighborhood), before `open_mount_veracrypt`.
- `test/`: add a new `test/disk.bats` (or extend `misc.bats`) covering both functions,
  with inline `lsblk`/`mount` stubs. Prefer a dedicated `test/disk.bats` for clarity.

## Risks / notes

- `numfmt --from=iec` treats `1G` as 1024³ (IEC), matching the "GiB" intent. A bare
  number passes through unchanged (raw bytes still work).
- `lsblk -l` avoids the tree-drawing characters that pollute `NAME` in default mode.
- `mount --mkdir` requires util-linux ≥ 2.35 — already relied upon by
  `open_mount_veracrypt`, so no new assumption.
- Both stop at the first failure; no partial-rollback (unmounting already-mounted
  devices) — out of scope, consistent with the rest of the plugin.
