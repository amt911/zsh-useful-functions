# Audit Fixes + open-partitions veracrypt & parallel — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix every item in `docs/superpowers/AUDIT-2026-07-01.md`, add a veracrypt/tcrypt unlock mode and opt-in parallel unlocking to `open-partitions`.

**Architecture:** Single sourced zsh file (`zsh-useful-functions.zsh`). Bug fixes are localized per function. Image funcs are rewritten to parse real flags with `zparseopts` (mirroring the existing `open-partitions` rewrite) and to prefer `magick` over the deprecated `convert`. `open-partitions` gains a shared per-device unlock helper reused by a new veracrypt mode and by a `-p` parallel path.

**Tech Stack:** zsh, `cryptsetup`, `systemd-cryptsetup`, ImageMagick (`magick`/`convert`), coreutils, bats-core for tests.

## Global Constraints

- Target shell is **zsh**; zsh-only syntax is expected (`${var:t}`, `**` globs, glob qualifiers, `local -r`, `commands`/`$+commands`).
- **Preserve existing style:** `local -r` for constants, explicit `unset` of loop vars at end of each function, `[ ]`-style POSIX tests, usage banner on `argc == 0` or invalid input, explicit non-zero `return` codes.
- **Secrets:** any function reading a password/PIM must `unset` it before returning.
- **No new external tool dependencies** — `magick`/`convert` are the same ImageMagick package; pick whichever is installed.
- **Lint:** `shellcheck --shell=bash zsh-useful-functions.zsh` (zsh-only constructs may warn — judge per case, do not "fix" them into bash).
- **Test runner:** `bats test/`. Tests source `$PLUGIN_FILE` and stub external tools (see `test/test_helper.bash`). Destructive/hardware cores (`open_mount_veracrypt` real unlock+mount, `btrfs_*`, real `dd`) are covered on arg-parsing/usage paths only.
- Branch: `feat/audit-fixes-veracrypt-parallel` (already created).

---

## File Structure

- Modify: `zsh-useful-functions.zsh` — all function fixes and rewrites.
- Modify: `test/test_helper.bash` — add a generic `run_plugin` helper that stubs `cryptsetup`, `systemd-cryptsetup`, `magick`, `convert`.
- Modify: `test/open-partitions.bats` — veracrypt + parallel + fido2/parallel tests.
- Create: `test/image.bats` — flag parsing / usage / output-path tests for the three image funcs.
- Create: `test/misc.bats` — `rand*`, `check_hashes`, `create_random_files`, `iommu_groups`, and the `check_binary_contents` IFS-preservation test.

---

## Task 1: Test harness — generic `run_plugin` helper

**Files:**
- Modify: `test/test_helper.bash`

**Interfaces:**
- Produces: `run_plugin <fn> <args...>` — bats helper that stubs `cryptsetup`/`systemd-cryptsetup` (echo `CS:`/`SC:`) and `magick`/`convert` (echo `IM:`), sources the plugin, then runs `<fn> <args...>` in the current working directory. Forwards stdin. Existing `run_op`/`run_op_legacy` stay unchanged.

- [ ] **Step 1: Add the helper to `test/test_helper.bash`**

Append to `test/test_helper.bash`:

```bash

# Generic: stub external tools, source the plugin, then run the given command.
# Runs in the current working directory — cd into "$BATS_TEST_TMPDIR" first in
# tests that touch the filesystem. Stdin is forwarded (for password/PIM prompts).
run_plugin() {
    run zsh -c '
        cryptsetup(){ print "CS:$*"; return 0; }
        systemd-cryptsetup(){ print "SC:$*"; return 0; }
        magick(){ print "IM:$*"; return 0; }
        convert(){ print "IM:$*"; return 0; }
        source "$1"; shift
        "$@"
    ' _ "$PLUGIN_FILE" "$@"
}
```

- [ ] **Step 2: Verify the harness still loads**

Run: `bats test/smoke.bats`
Expected: 1 test, PASS (helper is additive; nothing else changes yet).

- [ ] **Step 3: Commit**

```bash
git add test/test_helper.bash
git commit -m "test: add generic run_plugin bats helper"
```

---

## Task 2: `check_binary_contents` / `_cmp` — IFS + path rewrite (A1, A8, A11)

**Files:**
- Modify: `zsh-useful-functions.zsh` (lines ~218, 225, 314, 321)
- Create: `test/misc.bats`

**Interfaces:**
- Consumes: `run_plugin` (Task 1).
- Produces: nothing new (behavior fixes).

- [ ] **Step 1: Write the failing test**

Create `test/misc.bats` with:

```bash
load test_helper

@test "check_binary_contents preserves IFS" {
    cd "$BATS_TEST_TMPDIR"
    mkdir -p root/a/sub root/b/sub
    printf 'same' > root/a/sub/f.bin
    printf 'same' > root/b/sub/f.bin
    run zsh -c '
        source "$1"; shift
        before=$IFS
        check_binary_contents "$@" >/dev/null
        [ "$IFS" = "$before" ] && print "IFS-OK"
    ' _ "$PLUGIN_FILE" root a b
    [ "$status" -eq 0 ]
    [[ "$output" == *"IFS-OK"* ]]
}

@test "check_binary_contents finds the mirrored file (path rewrite)" {
    cd "$BATS_TEST_TMPDIR"
    mkdir -p root/a/sub root/b/sub
    printf 'same' > root/a/sub/f.bin
    printf 'same' > root/b/sub/f.bin
    run_plugin check_binary_contents root a b
    [ "$status" -eq 0 ]
    [[ "$output" == *"Both files are the same"* ]]
    [[ "$output" != *"does not exist on b"* ]]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats test/misc.bats`
Expected: FAIL — the IFS test fails because `old_ifs=IFS` sets the literal string, leaving `IFS` = "IFS" after restore.

- [ ] **Step 3: Fix `check_binary_contents`**

In `check_binary_contents`, change line ~218:

```zsh
    local old_ifs=$IFS
```

Change the loop body line ~225 (declare `other_dir` local, replace the `sed`):

```zsh
        local other_dir="$1/$3/${file#$1/$2/}"
```

Add `other_dir` and the segment vars to a `local` line just after `local old_ifs=$IFS` (the segment vars already have a `local` line — leave it; just ensure `other_dir` is declared as above inside the loop).

- [ ] **Step 4: Fix `check_binary_contents_cmp` identically**

Change line ~314:

```zsh
    local old_ifs=$IFS
```

Change line ~321:

```zsh
        local other_dir="$1/$3/${file#$1/$2/}"
```

- [ ] **Step 5: Run to verify it passes**

Run: `bats test/misc.bats`
Expected: both tests PASS.

- [ ] **Step 6: Commit**

```bash
git add zsh-useful-functions.zsh test/misc.bats
git commit -m "fix: correct IFS save/restore and robust path rewrite in check_binary_contents (P1)"
```

---

## Task 3: `rand` / `rand_letters` / `rand_num` — `/dev/urandom` (A6)

**Files:**
- Modify: `zsh-useful-functions.zsh` (lines 125, 135, 145)
- Modify: `test/misc.bats`

- [ ] **Step 1: Write the failing test**

Append to `test/misc.bats`:

```bash
@test "rand honors requested length and charset" {
    run zsh -c 'source "$1"; rand 12' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [ "${#output}" -eq 12 ]
    [[ "$output" =~ ^[a-zA-Z0-9]+$ ]]
}

@test "rand_num returns only digits" {
    run zsh -c 'source "$1"; rand_num 8' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [ "${#output}" -eq 8 ]
    [[ "$output" =~ ^[0-9]+$ ]]
}

@test "rand_letters returns only letters" {
    run zsh -c 'source "$1"; rand_letters 8' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [ "${#output}" -eq 8 ]
    [[ "$output" =~ ^[a-zA-Z]+$ ]]
}
```

- [ ] **Step 2: Run to verify**

Run: `bats test/misc.bats`
Expected: the three `rand*` tests PASS or hang. On a machine low on entropy they can **block** on `/dev/random` (the bug). Ctrl-C and proceed to the fix.

- [ ] **Step 3: Fix the three functions**

Replace `/dev/random` with `/dev/urandom` on lines 125, 135, 145:

```zsh
    tr -dc "a-zA-Z0-9" < /dev/urandom | head -c "$LEN"
```
```zsh
    tr -dc "a-zA-Z" < /dev/urandom | head -c "$LEN"
```
```zsh
    tr -dc "0-9" < /dev/urandom | head -c "$LEN"
```

- [ ] **Step 4: Run to verify it passes**

Run: `bats test/misc.bats`
Expected: all `rand*` tests PASS, no blocking.

- [ ] **Step 5: Commit**

```bash
git add zsh-useful-functions.zsh test/misc.bats
git commit -m "fix: use /dev/urandom in rand/rand_letters/rand_num to avoid blocking (P2)"
```

---

## Task 4: `create_random_files` — size bug + guard (A5)

**Files:**
- Modify: `zsh-useful-functions.zsh` (lines 148–177)
- Modify: `test/misc.bats`

- [ ] **Step 1: Write the failing test**

Append to `test/misc.bats`:

```bash
@test "create_random_files rejects max < min" {
    run zsh -c 'source "$1"; create_random_files 1 5 2 "$2"' _ "$PLUGIN_FILE" "$BATS_TEST_TMPDIR"
    [ "$status" -ne 0 ]
    [[ "$output" == *"max-size"* ]]
}

@test "create_random_files with no args prints usage" {
    run zsh -c 'source "$1"; create_random_files' _ "$PLUGIN_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: create_random_files"* ]]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats test/misc.bats`
Expected: FAIL — "rejects max < min" fails because there is no guard today (it would attempt `dd` with a bad `bs`).

- [ ] **Step 3: Fix the 4-arg branch**

Replace the body of the `if [ "$#" -eq "4" ]` branch (the `for` loop and its surroundings, lines ~168–172) with:

```zsh
        local -r RANGE=$(( MAX - MIN + 1 ))
        if [ "$RANGE" -le 0 ];
        then
            echo "Error: max-size must be >= min-size" >&2
            return 1
        fi

        local i size
        for (( i=0; i<NUM_FILES; i++ ))
        do
            size=$(( MIN + RANDOM % RANGE ))
            (( size < 1 )) && size=1
            dd if=/dev/urandom of="$DIR/$(rand)" bs="${size}M" count=1
        done
        unset i size
```

- [ ] **Step 4: Run to verify it passes**

Run: `bats test/misc.bats`
Expected: both new tests PASS.

- [ ] **Step 5: Commit**

```bash
git add zsh-useful-functions.zsh test/misc.bats
git commit -m "fix: bound create_random_files block size and guard max<min (P1)"
```

---

## Task 5: `check_hashes` — mktemp + colors + usage (A4, A7)

**Files:**
- Modify: `zsh-useful-functions.zsh` (lines 179–194)
- Modify: `test/misc.bats`

- [ ] **Step 1: Write the failing test**

Append to `test/misc.bats`:

```bash
@test "check_hashes does not clobber ./aux" {
    cd "$BATS_TEST_TMPDIR"
    printf 'PRECIOUS' > aux
    printf 'deadbeef  file1\n' > h1
    printf 'deadbeef  file1\n' > h2
    run_plugin check_hashes h1 h2
    [ "$status" -eq 0 ]
    [ "$(cat aux)" = "PRECIOUS" ]
    [[ "$output" == *"OK"* ]]
}

@test "check_hashes with wrong arg count prints usage" {
    run zsh -c 'source "$1"; check_hashes onlyone' _ "$PLUGIN_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: check_hashes"* ]]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats test/misc.bats`
Expected: FAIL — the clobber test fails (`aux` is overwritten then `rm`'d), and there is no usage guard.

- [ ] **Step 3: Rewrite `check_hashes`**

Replace the whole function (lines 179–194):

```zsh
# $1: First hash file
# $2: Second hash file
check_hashes(){
    if [ "$#" -ne 2 ];
    then
        echo "Usage: check_hashes <first-hash-file> <second-hash-file>"
        return 1
    fi

    local -r GREEN=$'\e[32m' RED=$'\e[31m' NO_COLOR=$'\e[0m'
    local -r tmp="$(mktemp)"

    # Strip filename from first hash file
    awk '{print $1}' "$1" > "$tmp"

    local line
    while IFS= read -r line; do
        if grep -qi -- "$line" "$2";
        then
            echo -e "$line: ${GREEN}OK${NO_COLOR}"
        else
            echo -e "$line: ${RED}NOT FOUND${NO_COLOR}"
        fi
    done < "$tmp"

    rm -f "$tmp"
    unset line
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `bats test/misc.bats`
Expected: both new tests PASS; `./aux` untouched.

- [ ] **Step 5: Commit**

```bash
git add zsh-useful-functions.zsh test/misc.bats
git commit -m "fix: check_hashes uses mktemp, defines colors, adds usage guard (P1/P2)"
```

---

## Task 6: `iommu_groups` — zsh glob rewrite (A10)

**Files:**
- Modify: `zsh-useful-functions.zsh` (lines 354–365)
- Modify: `test/misc.bats`

- [ ] **Step 1: Write the failing test**

Append to `test/misc.bats`:

```bash
@test "iommu_groups runs without word-split errors" {
    if [ ! -d /sys/kernel/iommu_groups ]; then
        skip "no /sys/kernel/iommu_groups on this machine"
    fi
    run zsh -c 'source "$1"; iommu_groups' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run to verify**

Run: `bats test/misc.bats`
Expected: PASS or skip. (This test guards the rewrite from regressing; the rewrite's value is robustness, verified by review.)

- [ ] **Step 3: Rewrite `iommu_groups`**

Replace the whole function (lines 354–365):

```zsh
iommu_groups(){
    local g d
    # (/nN): directories only, numeric sort, nullglob — robust, no word-splitting.
    for g in /sys/kernel/iommu_groups/*(/nN); do
        echo "IOMMU Group ${g:t}:"
        for d in "$g"/devices/*(N); do
            echo -e "\t$(lspci -nns "${d:t}")"
        done
    done

    unset g d
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `bats test/misc.bats`
Expected: PASS or skip.

- [ ] **Step 5: Commit**

```bash
git add zsh-useful-functions.zsh test/misc.bats
git commit -m "refactor: iommu_groups uses zsh globs instead of find+word-splitting (P2)"
```

---

## Task 7: `open_mount_veracrypt` — print -rn (A2)

**Files:**
- Modify: `zsh-useful-functions.zsh` (lines 395, 406)
- Modify: `test/open-partitions.bats`

**Note:** the `echo`→`print -rn` change matters only to real `cryptsetup` (trailing `\n` → "No key available"); it is not observable through a `$*`-echoing stub. Per project rules this interactive/hardware function is tested on its arg-construction/usage paths only.

- [ ] **Step 1: Write the failing test**

Append to `test/open-partitions.bats`:

```bash
@test "open_mount_veracrypt bad first arg prints usage" {
    run zsh -c 'source "$1"; open_mount_veracrypt zzz' _ "$PLUGIN_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: mount_veracrypt"* ]]
}

@test "open_mount_veracrypt ascending builds veracrypt-pim unlock" {
    run zsh -c '
        cryptsetup(){ print "CS:$*"; return 0; }
        mount(){ print "MNT:$*"; return 0; }
        source "$1"
        open_mount_veracrypt 0 /dev/sda1 <<< $'"'"'pw\n1234'"'"'
    ' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CS:--type tcrypt --veracrypt-pim 1234 open /dev/sda1 veracrypt1 -"* ]]
}
```

- [ ] **Step 2: Run to verify**

Run: `bats test/open-partitions.bats`
Expected: both PASS (arg construction is unchanged by the fix; this pins current behavior before editing).

- [ ] **Step 3: Apply the fix**

Line 395:

```zsh
            print -rn -- "$password" | cryptsetup --type tcrypt --veracrypt-pim "$pim" open "${PARTITIONS[i]}" "veracrypt$(( i ))" -
```

Line 406:

```zsh
            print -rn -- "$password" | cryptsetup --type tcrypt --veracrypt-pim "$pim" open "${PARTITIONS[i]}" "veracrypt$(( 64 - i + 1 ))" -
```

- [ ] **Step 4: Run to verify it still passes**

Run: `bats test/open-partitions.bats`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add zsh-useful-functions.zsh test/open-partitions.bats
git commit -m "fix: open_mount_veracrypt feeds passphrase with print -rn, not echo (P1)"
```

---

## Task 8: `convert_png_to_jpg` — zparseopts + magick (A9)

**Files:**
- Modify: `zsh-useful-functions.zsh` (lines 9–39)
- Create: `test/image.bats`

**Interfaces:**
- Produces: `convert_png_to_jpg [-r] [<quality>] <path>` — `-r` recurses (`**/*.png`), else `*.png`; optional quality; prefers `magick`, falls back to `convert`.

- [ ] **Step 1: Write the failing test**

Create `test/image.bats`:

```bash
load test_helper

@test "convert_png_to_jpg no args prints usage" {
    run_plugin convert_png_to_jpg
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: convert_png_to_jpg"* ]]
}

@test "convert_png_to_jpg converts non-recursively, no quality" {
    cd "$BATS_TEST_TMPDIR"
    touch a.png
    mkdir sub; touch sub/b.png
    run_plugin convert_png_to_jpg .
    [ "$status" -eq 0 ]
    [[ "$output" == *"IM:./a.png ./a.jpg"* ]]
    [[ "$output" != *"b.png"* ]]
}

@test "convert_png_to_jpg -r recurses and applies quality" {
    cd "$BATS_TEST_TMPDIR"
    touch a.png
    mkdir sub; touch sub/b.png
    run_plugin convert_png_to_jpg -r 33 .
    [ "$status" -eq 0 ]
    [[ "$output" == *"-quality 33"* ]]
    [[ "$output" == *"sub/b.jpg"* ]]
}

@test "convert_png_to_jpg unknown flag errors" {
    run_plugin convert_png_to_jpg -x .
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid option"* ]]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats test/image.bats`
Expected: FAIL — current function counts `$#`, has no `-r` flag, no usage for `-x`.

- [ ] **Step 3: Rewrite `convert_png_to_jpg`**

Replace lines 9–39 (the `# REWRITE THIS FUNCTION...` comment and the function) with:

```zsh
# Convert PNG files to JPG.
convert_png_to_jpg() {
    local -a o_recursive o_help
    zparseopts -D -E -F -- r=o_recursive h=o_help -help=o_help 2>/dev/null
    local -r parse_rc=$?

    if [ "$parse_rc" -ne "0" ];
    then
        echo "Error: invalid option" >&2
        return 1
    fi

    if [ -n "$o_help" ] || [ "$#" -eq "0" ];
    then
        echo "Usage: convert_png_to_jpg [-r] [<quality>] <path>"
        echo "  -r          recurse into subdirectories"
        echo "  <quality>   optional JPEG quality (1-100)"
        echo "Example: convert_png_to_jpg ."
        echo "Example: convert_png_to_jpg -r 33 ."
        [ -n "$o_help" ] && return 0
        return 1
    fi

    local im=convert
    (( $+commands[magick] )) && im=magick

    local quality path
    if [ "$#" -eq "1" ];
    then
        path="$1"
    elif [ "$#" -eq "2" ];
    then
        quality="$1"; path="$2"
    else
        echo "Error: expected [<quality>] <path>" >&2
        return 1
    fi

    local -a pngs
    if [ -n "$o_recursive" ];
    then
        pngs=("$path"/**/*.png(N))
    else
        pngs=("$path"/*.png(N))
    fi

    local f jpg_name
    for f in "${pngs[@]}"; do
        jpg_name="${f/%.png/.jpg}"
        if [ -n "$quality" ];
        then
            "$im" "$f" -quality "$quality" "$jpg_name"
        else
            "$im" "$f" "$jpg_name"
        fi
    done
    unset f jpg_name
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `bats test/image.bats`
Expected: the four `convert_png_to_jpg` tests PASS.

- [ ] **Step 5: Commit**

```bash
git add zsh-useful-functions.zsh test/image.bats
git commit -m "refactor: convert_png_to_jpg parses -r/quality flags, prefers magick (P2/P3)"
```

---

## Task 9: `batch_resize` — zparseopts + magick + output path (A3, A9)

**Files:**
- Modify: `zsh-useful-functions.zsh` (lines 41–60)
- Modify: `test/image.bats`

**Interfaces:**
- Produces: `batch_resize [-f] <dir> <percentage>` — `-f` overwrites in place, else writes `resized/${f:t}`.

- [ ] **Step 1: Write the failing test**

Append to `test/image.bats`:

```bash
@test "batch_resize writes to resized/<basename> and creates the dir" {
    cd "$BATS_TEST_TMPDIR"
    touch a.png
    run_plugin batch_resize . 50%
    [ "$status" -eq 0 ]
    [[ "$output" == *"-resize 50%"* ]]
    [[ "$output" == *"resized/a.png"* ]]
    [ -d resized ]
}

@test "batch_resize -f resizes in place" {
    cd "$BATS_TEST_TMPDIR"
    touch a.png
    run_plugin batch_resize -f . 33%
    [ "$status" -eq 0 ]
    [[ "$output" == *"IM:./a.png -resize 33% -filter Point ./a.png"* ]]
    [ ! -d resized ]
}

@test "batch_resize wrong arg count prints usage" {
    run_plugin batch_resize .
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: batch_resize"* ]]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats test/image.bats`
Expected: FAIL — current code writes to `resized/$f` (nested, uncreated) and infers `-f` by arg count.

- [ ] **Step 3: Rewrite `batch_resize`**

Replace lines 41–60:

```zsh
batch_resize(){
    local -a o_inplace o_help
    zparseopts -D -E -F -- f=o_inplace h=o_help -help=o_help 2>/dev/null
    local -r parse_rc=$?

    if [ "$parse_rc" -ne "0" ];
    then
        echo "Error: invalid option" >&2
        return 1
    fi

    if [ -n "$o_help" ] || [ "$#" -ne "2" ];
    then
        echo "Usage: batch_resize [-f] <directory> <percentage>"
        echo "  -f    resize in place (overwrite originals); else write to resized/"
        echo "Example: batch_resize . 20%"
        echo "Example: batch_resize -f . 33%"
        [ -n "$o_help" ] && return 0
        return 1
    fi

    local im=convert
    (( $+commands[magick] )) && im=magick

    local -r dir="$1" pct="$2"
    [ -z "$o_inplace" ] && mkdir -p resized

    local f
    for f in "$dir"/*.png(N); do
        if [ -n "$o_inplace" ];
        then
            "$im" "$f" -resize "$pct" -filter Point "$f"
        else
            "$im" "$f" -resize "$pct" -filter Point "resized/${f:t}"
        fi
    done
    unset f
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `bats test/image.bats`
Expected: the three `batch_resize` tests PASS.

- [ ] **Step 5: Commit**

```bash
git add zsh-useful-functions.zsh test/image.bats
git commit -m "fix: batch_resize output path (resized/basename) + zparseopts + magick (P1/P2/P3)"
```

---

## Task 10: `batch_crop` — zparseopts + magick + output path (A3, A9)

**Files:**
- Modify: `zsh-useful-functions.zsh` (lines 62–80)
- Modify: `test/image.bats`

**Interfaces:**
- Produces: `batch_crop [-f] <dir> <geometry>` — `-f` overwrites in place, else writes `cropped/${f:t}`.

- [ ] **Step 1: Write the failing test**

Append to `test/image.bats`:

```bash
@test "batch_crop writes to cropped/<basename> and creates the dir" {
    cd "$BATS_TEST_TMPDIR"
    touch a.png
    run_plugin batch_crop . 12x13+1+2
    [ "$status" -eq 0 ]
    [[ "$output" == *"-crop 12x13+1+2"* ]]
    [[ "$output" == *"cropped/a.png"* ]]
    [ -d cropped ]
}

@test "batch_crop -f crops in place" {
    cd "$BATS_TEST_TMPDIR"
    touch a.png
    run_plugin batch_crop -f . 33x33
    [ "$status" -eq 0 ]
    [[ "$output" == *"IM:./a.png -crop 33x33 ./a.png"* ]]
    [ ! -d cropped ]
}

@test "batch_crop wrong arg count prints usage" {
    run_plugin batch_crop .
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: batch_crop"* ]]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats test/image.bats`
Expected: FAIL — same class of bug as `batch_resize`.

- [ ] **Step 3: Rewrite `batch_crop`**

Replace lines 62–80:

```zsh
batch_crop() {
    local -a o_inplace o_help
    zparseopts -D -E -F -- f=o_inplace h=o_help -help=o_help 2>/dev/null
    local -r parse_rc=$?

    if [ "$parse_rc" -ne "0" ];
    then
        echo "Error: invalid option" >&2
        return 1
    fi

    if [ -n "$o_help" ] || [ "$#" -ne "2" ];
    then
        echo "Usage: batch_crop [-f] <directory> {x}x{y}{+/-}{x}{+/-}{y}"
        echo "  -f    crop in place (overwrite originals); else write to cropped/"
        echo "Example: batch_crop . 12x13+1+2"
        echo "Example: batch_crop -f . 33x33"
        [ -n "$o_help" ] && return 0
        return 1
    fi

    local im=convert
    (( $+commands[magick] )) && im=magick

    local -r dir="$1" geom="$2"
    [ -z "$o_inplace" ] && mkdir -p cropped

    local f
    for f in "$dir"/*.png(N); do
        if [ -n "$o_inplace" ];
        then
            "$im" "$f" -crop "$geom" "$f"
        else
            "$im" "$f" -crop "$geom" "cropped/${f:t}"
        fi
    done
    unset f
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `bats test/image.bats`
Expected: the three `batch_crop` tests PASS.

- [ ] **Step 5: Commit**

```bash
git add zsh-useful-functions.zsh test/image.bats
git commit -m "fix: batch_crop output path (cropped/basename) + zparseopts + magick (P1/P2/P3)"
```

---

## Task 11: open-partitions — shared unlock helper + veracrypt mode (B1, B2)

**Files:**
- Modify: `zsh-useful-functions.zsh` (add helper before `open-partitions` at line ~428; edit `open-partitions` flag parsing, conflict check, prompt, and loop)
- Modify: `test/open-partitions.bats`

**Interfaces:**
- Consumes: `run_op` / `run_plugin`.
- Produces:
  - `_open_partitions_unlock <device>` — file-scope helper; dispatches on the dynamically-scoped mode vars (`o_fido`, `o_keyfile`, `o_vera`, `keyfile_loc`, `password`, `pim`); returns the unlock command's exit code.
  - `open-partitions [-k <keyfile> | -f | --fido2 | -v | --veracrypt] <device>...` — veracrypt mode prompts password+PIM once, unlocks each device with `cryptsetup --type tcrypt --veracrypt-pim "$pim" open <dev> <basename> -`. Mapper name stays `${i:t}`. No mount.

- [ ] **Step 1: Write the failing test**

Append to `test/open-partitions.bats`:

```bash
@test "veracrypt mode builds tcrypt unlock with basename mapper" {
    run zsh -c '
        cryptsetup(){ print "CS:$*"; return 0; }
        source "$1"
        open-partitions -v /dev/nvme1n1p4 <<< $'"'"'pw\n1234'"'"'
    ' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CS:--type tcrypt --veracrypt-pim 1234 open /dev/nvme1n1p4 nvme1n1p4 -"* ]]
}

@test "-v conflicts with -k" {
    run_op -v -k /root/key /dev/sda1
    [ "$status" -eq 1 ]
    [[ "$output" == *"mutually exclusive"* ]]
}

@test "-v conflicts with -f" {
    run_op -v -f /dev/sda1
    [ "$status" -eq 1 ]
    [[ "$output" == *"mutually exclusive"* ]]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats test/open-partitions.bats`
Expected: FAIL — `-v` is an unknown flag today (`invalid option`).

- [ ] **Step 3: Add the helper before `open-partitions`**

Insert immediately above the `open-partitions(){` definition (line ~428, after its comment block):

```zsh
# Unlock a single device according to the mode flags of the calling
# open-partitions invocation. zsh locals are dynamically scoped, so this sees
# the caller's o_fido/o_keyfile/o_vera/keyfile_loc/password/pim. Returns the
# unlock command's exit code.
_open_partitions_unlock() {
    local dev="$1" dm="${1:t}"

    if [ -n "$o_fido" ];
    then
        systemd-cryptsetup attach "$dm" "$dev" - fido2-device=auto
    elif [ -n "$o_keyfile" ];
    then
        cryptsetup --key-file "$keyfile_loc" open "$dev" "$dm"
    elif [ -n "$o_vera" ];
    then
        print -rn -- "$password" | cryptsetup --type tcrypt --veracrypt-pim "$pim" open "$dev" "$dm" -
    else
        print -rn -- "$password" | cryptsetup open "$dev" "$dm" -
    fi
}
```

- [ ] **Step 4: Extend `open-partitions` flag parsing and conflict check**

Change the `local -a` declaration (line 429):

```zsh
    local -a o_keyfile o_fido o_vera o_help
```

Change the `zparseopts` line (line 434) to add `-v`/`--veracrypt`:

```zsh
    zparseopts -D -E -F -- k:=o_keyfile f=o_fido -fido2=o_fido v=o_vera -veracrypt=o_vera h=o_help -help=o_help 2>/dev/null
```

Replace the conflict check (lines 454–458) with a mode count:

```zsh
    local -i mode_count=0
    [ -n "$o_keyfile" ] && (( mode_count++ ))
    [ -n "$o_fido" ] && (( mode_count++ ))
    [ -n "$o_vera" ] && (( mode_count++ ))
    if [ "$mode_count" -gt "1" ];
    then
        echo "Error: -k, -f/--fido2 and -v/--veracrypt are mutually exclusive" >&2
        return 1
    fi
```

- [ ] **Step 5: Add PIM prompting and rewrite the loop to use the helper**

Replace the password prompt block (lines 462–468) with:

```zsh
    local password="" pim=""
    if [ -z "$o_keyfile" ] && [ -z "$o_fido" ];
    then
        echo -n "Password: "
        read -rs password
        echo
        if [ -n "$o_vera" ];
        then
            echo -n "PIM: "
            read -rs pim
            echo
        fi
    fi
```

Replace the unlock loop (lines 470–494, from `local i dm_name` through `unset i dm_name`) with:

```zsh
    local i rc=0
    for i in "$@"
    do
        if ! _open_partitions_unlock "$i";
        then
            rc=1
            break
        fi
    done
    unset i

    # Unsets secrets to avoid a leak
    unset password pim
    return $rc
```

(The trailing `unset password` at line 497 is now handled above — remove the now-duplicate final `unset password` line if present.)

- [ ] **Step 6: Update the usage banner**

Replace the usage block inside `open-partitions` (lines 445–449) with:

```zsh
        echo "Usage: open-partitions [-k <keyfile> | -f | --fido2 | -v | --veracrypt] [-p] <device>..."
        echo "  (no flag)      password mode  — prompt once, unlock every device"
        echo "  -k <keyfile>   keyfile mode   — cryptsetup --key-file <keyfile>"
        echo "  -f, --fido2    FIDO2 mode     — systemd-cryptsetup attach ... fido2-device=auto"
        echo "  -v, --veracrypt veracrypt/tcrypt — prompt password+PIM once, cryptsetup --type tcrypt"
        echo "  -p, --parallel unlock devices concurrently (ignored for FIDO2)"
        echo "  -h, --help     show this help"
```

(`-p` is wired up in Task 12; documenting it now keeps the banner in one edit.)

- [ ] **Step 7: Run to verify it passes**

Run: `bats test/open-partitions.bats`
Expected: all tests PASS (existing password/keyfile/fido2 tests still green, new veracrypt/conflict tests green).

- [ ] **Step 8: Commit**

```bash
git add zsh-useful-functions.zsh test/open-partitions.bats
git commit -m "feat: add veracrypt/tcrypt mode to open-partitions via shared unlock helper"
```

---

## Task 12: open-partitions — opt-in parallel mode (B3)

**Files:**
- Modify: `zsh-useful-functions.zsh` (`open-partitions` flag parsing + dispatch)
- Modify: `test/open-partitions.bats`

**Interfaces:**
- Consumes: `_open_partitions_unlock` (Task 11).
- Produces: `open-partitions ... -p|--parallel ...` — backgrounds each unlock, waits on all, returns non-zero if any failed. FIDO2 always runs sequentially (warns if `-p -f` combined).

- [ ] **Step 1: Write the failing test**

Append to `test/open-partitions.bats`:

```bash
@test "parallel mode opens all devices" {
    run zsh -c '
        cryptsetup(){ print "CS:$*"; return 0; }
        source "$1"
        open-partitions -p /dev/sda1 /dev/sdb1 <<< "pw"
    ' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"open /dev/sda1 sda1 -"* ]]
    [[ "$output" == *"open /dev/sdb1 sdb1 -"* ]]
}

@test "parallel mode reports a failing device and returns non-zero" {
    run zsh -c '
        cryptsetup(){ print "CS:$*"; [[ "$*" == *sdb1* ]] && return 1; return 0; }
        source "$1"
        open-partitions -p /dev/sda1 /dev/sdb1 <<< "pw"
    ' _ "$PLUGIN_FILE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"failed to unlock /dev/sdb1"* ]]
}

@test "fido2 + parallel warns and runs sequentially" {
    run_op -f -p /dev/nvme1n1p1 /dev/nvme1n1p2
    [ "$status" -eq 0 ]
    [[ "$output" == *"ignoring --parallel"* ]]
    [[ "$output" == *"SC:attach nvme1n1p1 /dev/nvme1n1p1 - fido2-device=auto"* ]]
    [[ "$output" == *"SC:attach nvme1n1p2 /dev/nvme1n1p2 - fido2-device=auto"* ]]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats test/open-partitions.bats`
Expected: FAIL — `-p` is an unknown flag today.

- [ ] **Step 3: Add `-p`/`--parallel` to flag parsing**

Change the `local -a` declaration to add `o_parallel`:

```zsh
    local -a o_keyfile o_fido o_vera o_parallel o_help
```

Add `-p`/`--parallel` to the `zparseopts` line:

```zsh
    zparseopts -D -E -F -- k:=o_keyfile f=o_fido -fido2=o_fido v=o_vera -veracrypt=o_vera p=o_parallel -parallel=o_parallel h=o_help -help=o_help 2>/dev/null
```

- [ ] **Step 4: Add the FIDO2+parallel warning and the parallel dispatch**

Replace the sequential loop added in Task 11 (the `local i rc=0` … `return $rc` block) with:

```zsh
    if [ -n "$o_parallel" ] && [ -n "$o_fido" ];
    then
        echo "Warning: FIDO2 uses a hardware token; ignoring --parallel (running sequentially)" >&2
    fi

    local rc=0 i
    if [ -n "$o_parallel" ] && [ -z "$o_fido" ];
    then
        local -a pids
        local -A pid_dev
        local p
        for i in "$@"
        do
            _open_partitions_unlock "$i" &
            pids+=($!)
            pid_dev[$!]="$i"
        done
        for p in "${pids[@]}"
        do
            if ! wait "$p";
            then
                echo "Error: failed to unlock ${pid_dev[$p]}" >&2
                rc=1
            fi
        done
        unset p pids pid_dev
    else
        for i in "$@"
        do
            if ! _open_partitions_unlock "$i";
            then
                rc=1
                break
            fi
        done
    fi
    unset i

    # Unsets secrets to avoid a leak
    unset password pim
    return $rc
```

- [ ] **Step 5: Run to verify it passes**

Run: `bats test/open-partitions.bats`
Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add zsh-useful-functions.zsh test/open-partitions.bats
git commit -m "feat: add opt-in -p/--parallel mode to open-partitions"
```

---

## Task 13: Full-suite verification + lint + docs update

**Files:**
- Modify: `CLAUDE.md` (flip the "Tests: not implemented yet" note to reflect the now-real bats suite — only if accurate after this work)
- Modify: `README.md` (if it documents these functions — check first)

- [ ] **Step 1: Run the whole suite**

Run: `bats test/`
Expected: all tests across `smoke.bats`, `open-partitions.bats`, `image.bats`, `misc.bats` PASS. Capture the summary line.

- [ ] **Step 2: Lint**

Run: `shellcheck --shell=bash zsh-useful-functions.zsh || true`
Expected: review output. zsh-only constructs (`${f:t}`, glob qualifiers, `zparseopts`, `commands`, `print -rn`) may warn under the bash dialect — do not "fix" those into bash. Note any genuine issues.

- [ ] **Step 3: Update CLAUDE.md test note (only if now accurate)**

In `CLAUDE.md`, the "Tests and quality" section says the suite is "Not implemented yet." A bats suite now exists (`test/*.bats`). Update that paragraph to state bats is set up and how to run it (`bats test/`), keeping the coverage-gate caveat honest (still no coverage tool for zsh). Make the minimal truthful edit; do not rewrite the section wholesale.

- [ ] **Step 4: Verify docs edits didn't break anything**

Run: `bats test/`
Expected: unchanged — still all PASS (docs-only edits).

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: reflect the bats test suite now in place"
```

- [ ] **Step 6: Update the graph (per CLAUDE.md session-end rule)**

Run: `/graphify --update`
Expected: `graphify-out/` refreshed for the touched files. (Skill invocation, not a shell command.)

---

## Self-Review

**Spec coverage:**
- A1 IFS → Task 2. A2 echo → Task 7. A3 output paths → Tasks 9,10. A4 check_hashes → Task 5. A5 create_random_files → Task 4. A6 urandom → Task 3. A7 colors → Task 5. A8 sed→param → Task 2. A9 zparseopts+magick → Tasks 8,9,10. A10 iommu → Task 6. A11 locals → Tasks 2 (other_dir), 8 (jpg_name). ✔
- B1 veracrypt mode → Task 11. B2 helper → Task 11. B3 parallel → Task 12. B4 usage banner → Task 11 (with `-p` documented). ✔
- Test harness → Task 1. Verification/lint/docs → Task 13. ✔

**Placeholder scan:** No TBD/TODO/"handle edge cases"; every code step shows full code. ✔

**Type consistency:** `_open_partitions_unlock` signature (single `<device>` arg, reads dynamically-scoped mode vars) is identical in Tasks 11 and 12. Mode vars `o_keyfile/o_fido/o_vera/o_parallel/o_help` consistent across parsing, conflict check, prompt, dispatch. `im` selection (`local im=convert; (( $+commands[magick] )) && im=magick`) identical in Tasks 8/9/10. ✔
