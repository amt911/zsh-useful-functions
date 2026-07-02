# rsync_fanout + mount_partitions readonly/NTFS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `rsync_fanout` function (one source → many dests with fixed excludes) and extend `mount_partitions` with per-device readonly (`-r`) plus automatic NTFS mounting via `ntfs-3g`.

**Architecture:** `mount_partitions` gains a repeatable `-r` flag; a new module-level helper `_mount_partitions_one` decides the mount driver per device (native `mount` vs `ntfs-3g`, using `lsblk -no FSTYPE`) and the readonly flag. `rsync_fanout` is a standalone function that builds an `-avc` rsync command with built-in excludes and loops over destinations.

**Tech Stack:** zsh, `zparseopts`, util-linux (`lsblk`, `mount`), `ntfs-3g` (new dep), `rsync`. Tests: bats-core (`./test/bats/bin/bats test/`).

## Global Constraints

- Target shell zsh; option parsing via `zparseopts -D -E -F -- ...` (one line, `2>/dev/null`, check `$?` into `local -r parse_rc`).
- `local -r` for constants; explicit `unset` of loop vars at end of each function.
- `[ ]`-style POSIX tests; usage banner printed to stdout on `argc == 0`/invalid input; explicit non-zero `return` codes; `-h`/`--help` returns 0.
- TDD required: each new/changed function gets ≥1 happy-path and ≥1 usage-error test. Red → Green → Refactor.
- Run tests: `./test/bats/bin/bats test/`. Lint (manual): `shellcheck --shell=bash zsh-useful-functions.zsh` — ignore zsh-only false positives (`zparseopts`, `${x:t}`, `print -rn`).
- New external dependency `ntfs-3g` must be documented in `CLAUDE.md` (deliberate addition, user-requested).
- Tests stub external tools by defining a shell function that echoes its args and returns 0/1 (see `test/test_helper.bash` and `test/disk.bats`). Do NOT exercise real disks.

---

### Task 1: `mount_partitions` — per-device readonly (`-r`)

Add a repeatable `-r`/`--read-only` flag. Readonly devices mount with `mount -o ro --mkdir`; writable positional devices keep `mount --mkdir`. No NTFS handling yet (Task 2).

**Files:**
- Modify: `zsh-useful-functions.zsh:495-531` (the `mount_partitions` function)
- Test: `test/disk.bats`

**Interfaces:**
- Produces: `mount_partitions [-b <base>] [-r <device>]... [<device>...]`. Readonly devices → `mount -o ro --mkdir <dev> <base>/<basename>`; writable → `mount --mkdir <dev> <base>/<basename>`. Usage/`-h` unchanged in contract (returns 1 on no-work, 0 on `-h`).

- [ ] **Step 1: Write the failing tests**

Add to `test/disk.bats` (after the existing mount tests, before line 79's unknown-flag test is fine — append at end of file):

```bash
@test "mount_partitions -r mounts a device read-only" {
    run zsh -c "$_mount_ok"'; source "$1"; mount_partitions -r /dev/sda1' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"MNT:-o ro --mkdir /dev/sda1 /mnt/sda1"* ]]
}

@test "mount_partitions mixes read-only and writable devices in one call" {
    run zsh -c "$_mount_ok"'; source "$1"; mount_partitions -r /dev/nvme1n1p4 /dev/mapper/veracrypt1' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"MNT:-o ro --mkdir /dev/nvme1n1p4 /mnt/nvme1n1p4"* ]]
    [[ "$output" == *"MNT:--mkdir /dev/mapper/veracrypt1 /mnt/veracrypt1"* ]]
}

@test "mount_partitions with only -r (no positional) still mounts, no usage" {
    run zsh -c "$_mount_ok"'; source "$1"; mount_partitions -r /dev/sda1' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Usage: mount_partitions"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./test/bats/bin/bats test/disk.bats`
Expected: the three new tests FAIL (readonly path not implemented — `-r` treated as unknown flag → "invalid option", or `-o ro` absent).

- [ ] **Step 3: Implement the `-r` flag**

Replace the whole `mount_partitions` function (`zsh-useful-functions.zsh:495-531`) with:

```zsh
mount_partitions(){
    local -a o_base o_ro o_help
    zparseopts -D -E -F -- b:=o_base -base:=o_base r+:=o_ro -read-only+:=o_ro h=o_help -help=o_help 2>/dev/null
    local -r parse_rc=$?

    if [ "$parse_rc" -ne "0" ];
    then
        echo "Error: invalid option" >&2
        return 1
    fi

    if [ -n "$o_help" ] || { [ "$#" -eq "0" ] && [ "${#o_ro}" -eq "0" ]; };
    then
        echo "Usage: mount_partitions [-b <base-dir>] [-r <ro-device>]... <device>..."
        echo "  Mounts each <device> at <base-dir>/<device-basename>, creating the dir."
        echo "  -b, --base       base mount directory (default: /mnt)"
        echo "  -r, --read-only  mount this device read-only (repeatable)"
        echo "  -h, --help       show this help"
        echo "Example: mount_partitions -r /dev/nvme1n1p4 /dev/mapper/veracrypt1"
        echo "Example: mount_partitions -b /media /dev/sda1"
        [ -n "$o_help" ] && return 0
        return 1
    fi

    local -r base="${o_base[2]:-/mnt}"

    # zparseopts accumulates each -r occurrence; keep only the device values,
    # dropping any captured flag tokens (robust to both storage forms).
    local -a ro_devs
    local tok
    for tok in "${o_ro[@]}"
    do
        [ "$tok" = "-r" ] || [ "$tok" = "--read-only" ] && continue
        ro_devs+=("$tok")
    done
    unset tok

    local i target
    for i in "${ro_devs[@]}"
    do
        target="$base/${i:t}"
        if ! mount -o ro --mkdir "$i" "$target";
        then
            echo "Error: failed to mount $i at $target" >&2
            unset i target
            return 1
        fi
    done
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

- [ ] **Step 4: Run tests to verify they pass**

Run: `./test/bats/bin/bats test/disk.bats`
Expected: PASS — all mount tests (existing + 3 new) green.

- [ ] **Step 5: Commit**

```bash
git add zsh-useful-functions.zsh test/disk.bats
git commit -m "feat: mount_partitions -r flag to mount devices read-only

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `mount_partitions` — NTFS auto-detection via `ntfs-3g`

Detect NTFS per device with `lsblk -no FSTYPE` and mount those with `ntfs-3g` (creating the mountpoint first, since `ntfs-3g` has no `--mkdir`). Refactor the two mount loops through a new helper so the driver/readonly decision lives in one place.

**Files:**
- Modify: `zsh-useful-functions.zsh` (add helper `_mount_partitions_one` immediately above `mount_partitions`; simplify the two loops in `mount_partitions` to call it)
- Test: `test/disk.bats`

**Interfaces:**
- Consumes: the `mount_partitions` from Task 1.
- Produces: `_mount_partitions_one <ro:0|1> <device> <base>` → computes `target=<base>/<device-basename>`, mounts via `ntfs-3g` when `lsblk -no FSTYPE <device>` is `ntfs` (with `-o ro` when ro=1, after `mkdir -p <target>`) else via `mount [-o ro] --mkdir`. Prints `Error: failed to mount <dev> at <target>` to stderr and returns the driver's exit code.

- [ ] **Step 1: Write the failing tests**

First, make the existing non-NTFS mount tests deterministic now that the code calls `lsblk`. At the top of `test/disk.bats` add a stub for a non-NTFS filesystem, and add it to the four existing happy-path/failure mount tests **and** the Task 1 tests. Add near the other stub definitions (after line 42):

```bash
# lsblk FSTYPE stub: report a non-NTFS filesystem for any device.
_lsblk_ext4='lsblk(){ print "ext4"; }'
# lsblk FSTYPE stub: report NTFS for any device.
_lsblk_ntfs='lsblk(){ print "ntfs"; }'
```

Update the existing mount happy-path/failure tests to prepend `"$_lsblk_ext4"'; '` so `lsblk` is stubbed. For example change:

```bash
run zsh -c "$_mount_ok"'; source "$1"; mount_partitions /dev/mapper/veracrypt1' _ "$PLUGIN_FILE"
```
to:
```bash
run zsh -c "$_mount_ok"' ; '"$_lsblk_ext4"'; source "$1"; mount_partitions /dev/mapper/veracrypt1' _ "$PLUGIN_FILE"
```

Apply the same `"$_lsblk_ext4"` prepend to: "defaults base to /mnt", "honors -b base", "reports a mount failure", and the three Task 1 tests ("-r mounts read-only", "mixes read-only and writable", "only -r no positional").

Then add the NTFS tests at the end of the file:

```bash
# ntfs-3g stub echoing its args.
_ntfs_ok='ntfs-3g(){ print "NTFS3G:$*"; return 0; }'

@test "mount_partitions uses ntfs-3g for an NTFS device" {
    run zsh -c "$_mount_ok"' ; '"$_ntfs_ok"' ; '"$_lsblk_ntfs"'; source "$1"; mount_partitions /dev/sda1' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"NTFS3G:/dev/sda1 /mnt/sda1"* ]]
    [[ "$output" != *"MNT:"* ]]
}

@test "mount_partitions mounts an NTFS device read-only with -o ro" {
    run zsh -c "$_mount_ok"' ; '"$_ntfs_ok"' ; '"$_lsblk_ntfs"'; source "$1"; mount_partitions -r /dev/sda1' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"NTFS3G:-o ro /dev/sda1 /mnt/sda1"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./test/bats/bin/bats test/disk.bats`
Expected: the two NTFS tests FAIL (code still calls `mount`, so `NTFS3G:` absent / `MNT:` present). Existing + Task 1 tests still PASS.

- [ ] **Step 3: Add the helper and refactor the loops**

Insert this helper immediately **above** the `mount_partitions` function definition:

```zsh
# Mount a single device at <base>/<device-basename>. NTFS devices (per
# `lsblk -no FSTYPE`) use the ntfs-3g driver (mountpoint created first, since
# ntfs-3g has no --mkdir); others use native `mount --mkdir`. ro=1 adds -o ro.
# Prints an error and returns the driver's exit code on failure.
_mount_partitions_one() {
    local -r ro="$1" dev="$2" base="$3"
    local -r target="$base/${dev:t}"
    local fstype
    fstype="$(lsblk -no FSTYPE "$dev" 2>/dev/null)"

    local rc
    if [ "$fstype" = "ntfs" ];
    then
        if [ "$ro" = "1" ];
        then
            mkdir -p "$target" && ntfs-3g -o ro "$dev" "$target"
        else
            mkdir -p "$target" && ntfs-3g "$dev" "$target"
        fi
    else
        if [ "$ro" = "1" ];
        then
            mount -o ro --mkdir "$dev" "$target"
        else
            mount --mkdir "$dev" "$target"
        fi
    fi
    rc=$?

    if [ "$rc" -ne "0" ];
    then
        echo "Error: failed to mount $dev at $target" >&2
    fi
    return "$rc"
}
```

Then replace the two mount loops in `mount_partitions` (everything from `local i target` through the final `unset i target`) with:

```zsh
    local i
    for i in "${ro_devs[@]}"
    do
        _mount_partitions_one 1 "$i" "$base" || { unset i; return 1; }
    done
    for i in "$@"
    do
        _mount_partitions_one 0 "$i" "$base" || { unset i; return 1; }
    done
    unset i
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./test/bats/bin/bats test/disk.bats`
Expected: PASS — all mount tests including the two NTFS tests.

- [ ] **Step 5: Commit**

```bash
git add zsh-useful-functions.zsh test/disk.bats
git commit -m "feat: mount_partitions auto-mounts NTFS via ntfs-3g

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `rsync_fanout` function

One source → many destinations, `-avc` plus four built-in excludes; opt-in `--delete` and `--dry-run`; repeatable extra `--exclude`.

**Files:**
- Modify: `zsh-useful-functions.zsh` (add `rsync_fanout` in the disk-helpers area, e.g. after `mount_partitions`)
- Test: `test/disk.bats`

**Interfaces:**
- Produces: `rsync_fanout [-n|--dry-run] [-D|--delete] [-x|--exclude <pattern>]... <source> <dest>...`. Builds `rsync -avc [--dry-run] [--delete] --exclude 'System Volume Information' --exclude '$RECYCLE.BIN' --exclude 'Versiones anteriores' --exclude '.Trash-1000' [--exclude <extra>]... <source> <dest>` once per dest. Requires ≥2 positionals (source + ≥1 dest); usage error + return 1 otherwise; `-h` returns 0. Aborts on first rsync failure (return 1).

- [ ] **Step 1: Write the failing tests**

Add to `test/disk.bats` (end of file). Note the rsync stub prints `$*`; substring assertions tolerate the space-containing exclude values:

```bash
# rsync stub echoing its args; a failing variant for the abort test.
_rsync_ok='rsync(){ print "RS:$*"; return 0; }'
_rsync_fail='rsync(){ print "RS:$*"; return 1; }'

@test "rsync_fanout no args prints usage" {
    run zsh -c 'source "$1"; rsync_fanout' _ "$PLUGIN_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: rsync_fanout"* ]]
}

@test "rsync_fanout source but no dest prints usage" {
    run zsh -c 'source "$1"; rsync_fanout /mnt/src/' _ "$PLUGIN_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: rsync_fanout"* ]]
}

@test "rsync_fanout -h prints usage and returns 0" {
    run zsh -c 'source "$1"; rsync_fanout -h' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: rsync_fanout"* ]]
}

@test "rsync_fanout default uses -avc and built-in excludes, no delete/dry-run" {
    run zsh -c "$_rsync_ok"'; source "$1"; rsync_fanout /mnt/src/ /mnt/dst1' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RS:-avc "* ]]
    [[ "$output" == *"--exclude System Volume Information"* ]]
    [[ "$output" == *'--exclude $RECYCLE.BIN'* ]]
    [[ "$output" == *"--exclude Versiones anteriores"* ]]
    [[ "$output" == *"--exclude .Trash-1000"* ]]
    [[ "$output" == *"/mnt/src/ /mnt/dst1"* ]]
    [[ "$output" != *"--delete"* ]]
    [[ "$output" != *"--dry-run"* ]]
}

@test "rsync_fanout -D adds --delete and -n adds --dry-run" {
    run zsh -c "$_rsync_ok"'; source "$1"; rsync_fanout -D -n /mnt/src/ /mnt/dst1' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"--delete"* ]]
    [[ "$output" == *"--dry-run"* ]]
}

@test "rsync_fanout appends extra -x excludes after the built-ins" {
    run zsh -c "$_rsync_ok"'; source "$1"; rsync_fanout -x foo -x bar /mnt/src/ /mnt/dst1' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"--exclude foo"* ]]
    [[ "$output" == *"--exclude bar"* ]]
}

@test "rsync_fanout runs once per destination" {
    run zsh -c "$_rsync_ok"'; source "$1"; rsync_fanout /mnt/src/ /mnt/dst1 /mnt/dst2' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"/mnt/src/ /mnt/dst1"* ]]
    [[ "$output" == *"/mnt/src/ /mnt/dst2"* ]]
}

@test "rsync_fanout aborts on first rsync failure" {
    run zsh -c "$_rsync_fail"'; source "$1"; rsync_fanout /mnt/src/ /mnt/dst1 /mnt/dst2' _ "$PLUGIN_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"rsync to /mnt/dst1 failed"* ]]
    [[ "$output" != *"/mnt/src/ /mnt/dst2"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./test/bats/bin/bats test/disk.bats`
Expected: the new `rsync_fanout` tests FAIL ("command not found: rsync_fanout" → non-zero, usage strings absent).

- [ ] **Step 3: Implement `rsync_fanout`**

Add after the `mount_partitions` function:

```zsh
# Rsync one source to many destinations with a fixed set of excludes.
# Always uses -avc. --delete and --dry-run are opt-in. Aborts on first failure.
rsync_fanout(){
    local -a o_dry o_delete o_exclude o_help
    zparseopts -D -E -F -- n=o_dry -dry-run=o_dry D=o_delete -delete=o_delete x+:=o_exclude -exclude+:=o_exclude h=o_help -help=o_help 2>/dev/null
    local -r parse_rc=$?

    if [ "$parse_rc" -ne "0" ];
    then
        echo "Error: invalid option" >&2
        return 1
    fi

    if [ -n "$o_help" ] || [ "$#" -lt "2" ];
    then
        echo "Usage: rsync_fanout [-n] [-D] [-x <pattern>]... <source> <dest>..."
        echo "  Rsync <source> to every <dest> with -avc and a fixed set of excludes."
        echo "  -n, --dry-run   pass --dry-run to rsync (no changes made)"
        echo "  -D, --delete    pass --delete to rsync (destructive; off by default)"
        echo "  -x, --exclude   extra --exclude pattern (repeatable)"
        echo "  -h, --help      show this help"
        echo "  Built-in excludes: 'System Volume Information', '\$RECYCLE.BIN',"
        echo "                     'Versiones anteriores', '.Trash-1000'"
        echo "Example: rsync_fanout -D /mnt/nvme1n1p4/ /mnt/veracrypt1 /mnt/veracrypt2"
        [ -n "$o_help" ] && return 0
        return 1
    fi

    local -r source="$1"
    shift

    local -a rsync_flags
    rsync_flags=( -avc )
    [ -n "$o_dry" ] && rsync_flags+=( --dry-run )
    [ -n "$o_delete" ] && rsync_flags+=( --delete )

    local -a excludes
    excludes=(
        --exclude 'System Volume Information'
        --exclude '$RECYCLE.BIN'
        --exclude 'Versiones anteriores'
        --exclude '.Trash-1000'
    )

    # Append any extra -x/--exclude patterns, dropping captured flag tokens.
    local tok
    for tok in "${o_exclude[@]}"
    do
        [ "$tok" = "-x" ] || [ "$tok" = "--exclude" ] && continue
        excludes+=( --exclude "$tok" )
    done
    unset tok

    local d
    for d in "$@"
    do
        if ! rsync "${rsync_flags[@]}" "${excludes[@]}" "$source" "$d";
        then
            echo "Error: rsync to $d failed" >&2
            unset d
            return 1
        fi
    done
    unset d
}
```

- [ ] **Step 4: Run the full suite to verify it passes**

Run: `./test/bats/bin/bats test/`
Expected: PASS — all suites, including every new `rsync_fanout` test.

- [ ] **Step 5: Commit**

```bash
git add zsh-useful-functions.zsh test/disk.bats
git commit -m "feat: add rsync_fanout for one source to many destinations

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Docs — record the `ntfs-3g` dependency and new helpers

**Files:**
- Modify: `CLAUDE.md` (external CLI dependencies list under "Stack")
- Modify: `README.md` if it exists and lists functions/deps (check first: `ls README*`)

**Interfaces:** none (documentation only).

- [ ] **Step 1: Update the dependency list in `CLAUDE.md`**

In the "External CLI dependencies" bullet under **Stack**, add `ntfs-3g` and `rsync` to the enumerated tools. Change the coreutils/util-linux portion to also mention them, e.g. append: `, ntfs-3g (NTFS mounts in mount_partitions), rsync (rsync_fanout)`.

- [ ] **Step 2: Update README if present**

Run: `ls README* 2>/dev/null`
If a README lists functions or dependencies, add one line each for `rsync_fanout` and the `mount_partitions` `-r`/NTFS behavior, and add `ntfs-3g`/`rsync` to any dependency list. If no README exists, skip.

- [ ] **Step 3: Run shellcheck (manual sanity, expect only zsh false positives)**

Run: `shellcheck --shell=bash zsh-useful-functions.zsh || true`
Expected: no NEW real errors beyond the known zsh-only false positives (`zparseopts`, `${x:t}`, `print -rn`, glob qualifiers).

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md README* 2>/dev/null; git add CLAUDE.md
git commit -m "docs: note ntfs-3g/rsync deps and new mount/rsync helpers

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- `mount_partitions -r` per-device readonly → Task 1. ✓
- NTFS detection + `ntfs-3g` (readonly `-o ro`, `mkdir -p` first) → Task 2. ✓
- `-b`/`--base` unchanged → preserved in Task 1 rewrite. ✓
- `rsync_fanout` signature, `-avc`, opt-in `-D`/`--delete`, `-n`/`--dry-run`, repeatable `-x`, four built-in excludes, verbatim source/dest, abort on first failure → Task 3. ✓
- New dep `ntfs-3g` documented → Task 4. ✓
- TDD (happy + usage-error per function), stub-based tests → all tasks. ✓
- Ordering (readonly mounted first, then writable) → Task 1/2 loop order. ✓

**Placeholder scan:** No TBD/TODO; all code and commands shown in full. ✓

**Type/name consistency:** `_mount_partitions_one <ro> <dev> <base>` signature matches its callers in Task 2; `o_ro`/`o_exclude` filter loops use identical drop-flag-token idiom; stub names (`_mount_ok`, `_lsblk_ext4`, `_lsblk_ntfs`, `_ntfs_ok`, `_rsync_ok`, `_rsync_fail`) consistent across tasks. ✓

**Note on `zparseopts` repeatable capture:** the `r+:`/`x+:` specs accumulate each occurrence; the drop-flag-token loops (`[ "$tok" = "-r" ] && continue`) are correct whether zparseopts stores `(-r val -r val)` or `(val val)`. Verify empirically during Task 1 Step 4 — if the readonly device is dropped, print `${o_ro[@]}` to inspect the stored form and adjust the filter.
