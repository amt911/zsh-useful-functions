# partitions_by_size + mount_partitions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two disk helper functions to `zsh-useful-functions.zsh`: `partitions_by_size` (list partitions in an inclusive size range) and `mount_partitions` (mount devices under a base dir, one folder per device).

**Architecture:** Both are pure-logic functions over one external command each (`lsblk` / `mount`), so both are fully unit-testable by stubbing that command. They live after `iommu_groups` in the single sourced plugin file. Tests go in a new `test/disk.bats`.

**Tech Stack:** zsh, `lsblk` (util-linux), `numfmt` (coreutils), `mount --mkdir` (util-linux ≥ 2.35), bats-core.

## Global Constraints

- Target shell **zsh**; use zsh idioms (`${var:t}`, `zparseopts -D -E -F`, `local -r`).
- Preserve existing style: usage banner on `argc == 0`/invalid input, `[ ]` POSIX tests, explicit `unset` of loop vars, explicit non-zero `return`.
- **No new external tool dependencies.** Use `lsblk`, `numfmt`, `mount` (already assumed). **Do NOT use `jq`.**
- Bats is NOT on PATH — run via `./test/bats/bin/bats test/` (never a bare `bats`).
- Tests stub the external command (`lsblk`/`mount`); `numfmt` runs for real.
- Branch: `feat/audit-fixes-veracrypt-parallel` (existing).
- Both functions go after `iommu_groups`, before `open_mount_veracrypt`.

---

## File Structure

- Modify: `zsh-useful-functions.zsh` — add both functions after `iommu_groups`.
- Create: `test/disk.bats` — tests for both functions with inline `lsblk`/`mount` stubs.

---

## Task 1: `partitions_by_size`

**Files:**
- Modify: `zsh-useful-functions.zsh` (insert after the `iommu_groups` function)
- Create: `test/disk.bats`

**Interfaces:**
- Produces: `partitions_by_size <min-size> <max-size>` — prints `NAME<TAB>SIZE_bytes` for every partition (`TYPE == part`) whose byte size is in `[min, max]` inclusive. Sizes accept IEC suffixes (`K/M/G/T`, base 1024) or raw bytes via `numfmt --from=iec`. Usage on `$# != 2`; error+`return 1` on invalid size or `min > max`.

- [ ] **Step 1: Write the failing tests**

Create `test/disk.bats`:

```bash
load test_helper

# lsblk stub emitting NAME SIZE TYPE rows (bytes). One disk + four partitions.
# 512MiB=536870912, 1GiB=1073741824, 2GiB=2147483648, 5GiB=5368709120.
_lsblk_stub='lsblk(){ printf "%s\n" \
  "nvme0n1 500107862016 disk" \
  "nvme0n1p1 536870912 part" \
  "nvme0n1p2 1073741824 part" \
  "nvme0n1p3 2147483648 part" \
  "nvme0n1p4 5368709120 part"; }'

@test "partitions_by_size wrong arg count prints usage" {
    run zsh -c 'source "$1"; partitions_by_size 1G' _ "$PLUGIN_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: partitions_by_size"* ]]
}

@test "partitions_by_size rejects an invalid size" {
    run zsh -c 'source "$1"; partitions_by_size zzz 2G' _ "$PLUGIN_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid size"* ]]
}

@test "partitions_by_size rejects min greater than max" {
    run zsh -c 'source "$1"; partitions_by_size 3G 1G' _ "$PLUGIN_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"min-size must be <= max-size"* ]]
}

@test "partitions_by_size filters to the inclusive range and excludes disks" {
    run zsh -c "$_lsblk_stub"'; source "$1"; partitions_by_size 1G 2G' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"nvme0n1p2	1073741824"* ]]   # 1GiB, lower border inclusive
    [[ "$output" == *"nvme0n1p3	2147483648"* ]]   # 2GiB, upper border inclusive
    [[ "$output" != *"nvme0n1p1"* ]]               # 512MiB below range
    [[ "$output" != *"nvme0n1p4"* ]]               # 5GiB above range
    [[ "$output" != *"nvme0n1 "* ]]                # disk excluded
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `./test/bats/bin/bats test/disk.bats`
Expected: FAIL — `partitions_by_size` is not defined yet ("command not found").

- [ ] **Step 3: Implement `partitions_by_size`**

In `zsh-useful-functions.zsh`, immediately after the closing `}` of `iommu_groups`, insert:

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

- [ ] **Step 4: Run to verify they pass**

Run: `./test/bats/bin/bats test/disk.bats`
Expected: the four `partitions_by_size` tests PASS.

- [ ] **Step 5: Run the full suite (no regressions)**

Run: `./test/bats/bin/bats test/`
Expected: all prior tests still PASS plus the new ones.

- [ ] **Step 6: Commit**

```bash
git add zsh-useful-functions.zsh test/disk.bats
git commit -m "feat: add partitions_by_size to list partitions within a size range"
```

---

## Task 2: `mount_partitions`

**Files:**
- Modify: `zsh-useful-functions.zsh` (insert after `partitions_by_size`)
- Modify: `test/disk.bats`

**Interfaces:**
- Consumes: nothing from Task 1 (independent function).
- Produces: `mount_partitions [-b <base> | --base <base>] <device>...` — mounts each device at `<base>/<device-basename>` via `mount --mkdir`, base defaults to `/mnt`. Usage on `argc == 0`; `-h`/`--help` → usage + `return 0`; invalid flag → `return 1`; first mount failure → error + `return 1`.

- [ ] **Step 1: Write the failing tests**

Append to `test/disk.bats`:

```bash
# mount stub echoing its args; a second stub variant fails.
_mount_ok='mount(){ print "MNT:$*"; return 0; }'
_mount_fail='mount(){ print "MNT:$*"; return 1; }'

@test "mount_partitions no args prints usage" {
    run zsh -c 'source "$1"; mount_partitions' _ "$PLUGIN_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: mount_partitions"* ]]
}

@test "mount_partitions -h prints usage and returns 0" {
    run zsh -c 'source "$1"; mount_partitions -h' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: mount_partitions"* ]]
}

@test "mount_partitions defaults base to /mnt and derives folder from basename" {
    run zsh -c "$_mount_ok"'; source "$1"; mount_partitions /dev/mapper/veracrypt1' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"MNT:--mkdir /dev/mapper/veracrypt1 /mnt/veracrypt1"* ]]
}

@test "mount_partitions honors -b base and mounts multiple devices" {
    run zsh -c "$_mount_ok"'; source "$1"; mount_partitions -b /media /dev/sda1 /dev/sdb2' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"MNT:--mkdir /dev/sda1 /media/sda1"* ]]
    [[ "$output" == *"MNT:--mkdir /dev/sdb2 /media/sdb2"* ]]
}

@test "mount_partitions reports a mount failure and returns non-zero" {
    run zsh -c "$_mount_fail"'; source "$1"; mount_partitions /dev/sda1' _ "$PLUGIN_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"failed to mount /dev/sda1 at /mnt/sda1"* ]]
}

@test "mount_partitions rejects an unknown flag" {
    run zsh -c 'source "$1"; mount_partitions -x /dev/sda1' _ "$PLUGIN_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid option"* ]]
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `./test/bats/bin/bats test/disk.bats`
Expected: the six `mount_partitions` tests FAIL — function not defined yet.

- [ ] **Step 3: Implement `mount_partitions`**

In `zsh-useful-functions.zsh`, immediately after the closing `}` of `partitions_by_size`, insert:

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

- [ ] **Step 4: Run to verify they pass**

Run: `./test/bats/bin/bats test/disk.bats`
Expected: all `mount_partitions` tests PASS (and the Task 1 tests still PASS).

- [ ] **Step 5: Run the full suite (no regressions)**

Run: `./test/bats/bin/bats test/`
Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add zsh-useful-functions.zsh test/disk.bats
git commit -m "feat: add mount_partitions to mount devices under a base dir"
```

---

## Task 3: Full-suite verify + lint

**Files:** none (verification only).

- [ ] **Step 1: Run the whole suite**

Run: `./test/bats/bin/bats test/`
Expected: every test PASSES. Capture the summary line.

- [ ] **Step 2: Lint**

Run: `shellcheck --shell=bash zsh-useful-functions.zsh || true`
Expected: only the known zsh-dialect false positives (glob qualifiers `(N)`/`(/nN)`, `zparseopts`, `$+commands`, `print -rn`, process substitution `< <(...)`). Confirm no NEW genuine bug is reported for the two added functions. `numfmt`/`lsblk`/`mount` calls are plain external commands and should not add findings.

- [ ] **Step 3: (No docs change required)**

`CLAUDE.md` already documents the bats suite and `lsblk`/coreutils dependencies; both new functions use already-listed tools. No documentation edit needed. Confirm by re-reading the "External CLI dependencies" and "Tests and quality" lines — if `lsblk` is not listed there, add it; otherwise make no change.

---

## Self-Review

**Spec coverage:**
- `partitions_by_size` (interface, IEC parse, inclusive borders, `part` filter, usage, invalid-size, min>max) → Task 1. ✔
- `mount_partitions` (`-b`/`--base`, default `/mnt`, `${dev:t}` folder, `mount --mkdir`, usage, help, invalid flag, first-failure return) → Task 2. ✔
- No-jq / no-new-deps constraint → honored in both (lsblk+numfmt+mount only). ✔
- Placement after `iommu_groups`, tests in `test/disk.bats` → Tasks 1-2. ✔
- Verify + lint → Task 3. ✔

**Placeholder scan:** No TBD/TODO/"handle edge cases"; every code step shows full code and exact commands. ✔

**Type consistency:** Function names (`partitions_by_size`, `mount_partitions`), the `MNT:` stub prefix, the tab-separated `NAME<TAB>SIZE` output, and the `-b`/`--base` flag names are used identically across the plan's tasks and tests. ✔
