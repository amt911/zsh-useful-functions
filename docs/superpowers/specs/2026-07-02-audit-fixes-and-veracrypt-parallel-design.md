# Design — Audit fixes + open-partitions veracrypt & parallel

**Date:** 2026-07-02
**Branch:** `feat/audit-fixes-veracrypt-parallel` (new)
**Source audit:** `docs/superpowers/AUDIT-2026-07-01.md`

## Goals

1. Fix **all** items in the 2026-07-01 audit.
2. Add a **veracrypt/tcrypt** unlock mode to `open-partitions`.
3. Add **opt-in parallel** unlocking to `open-partitions`.

Non-goal: changing `open_mount_veracrypt`'s mount + auto-numbering behavior. It
stays a standalone tool; only its `echo`→`print -rn` bug is fixed.

## Workstream A — Audit fixes

Severity from the audit. TDD (bats) for arg-parsing / usage / path-construction
paths; destructive/hardware cores exercised via stubs (as existing tests do for
`cryptsetup`).

### A1. `check_binary_contents` / `_cmp` — P1 `old_ifs`
`local old_ifs=IFS` → `local old_ifs=$IFS` (lines 218, 314). Currently stores the
literal string "IFS" and on restore leaves `IFS` broken for the rest of the shell.

### A2. `open_mount_veracrypt` — P1 `echo` newline
`echo "$password" | cryptsetup ...` (395, 406) → `print -rn -- "$password" | ...`.
Same fix already applied in `open-partitions`.

### A3. `batch_resize` / `batch_crop` — P1 broken output path
`for f in "$1"/*.png` yields `dir/name.png`; `resized/$f` = `resized/dir/name.png`
(uncreated subdir). Fix: write to `resized/${f:t}` (`cropped/${f:t}`) and `mkdir -p`.

### A4. `check_hashes` — P1 clobbers `./aux`
Creates and `rm aux` in CWD, destroying a user's `aux`. Replace with `mktemp`;
`rm` the temp on exit. Also quote `$1`, `local` the loop var, silence `grep -q`.

### A5. `create_random_files` — P1 size bug
`bs=$(( MIN + $(rand_num) % MAX ))M`: `rand_num` (no arg) = 16-digit number, and
`MAX==0` divides by zero. Fix: bounded random via `$RANDOM`
(`bs=$(( MIN + RANDOM % (MAX - MIN + 1) ))M`), guard `MAX >= MIN` and `MAX>0`.
`local` the loop var. Optional: collision check on `of` name.

### A6. `rand` / `rand_letters` / `rand_num` — P2 `/dev/random` blocks
`/dev/random` → `/dev/urandom` (non-blocking, equivalent here). Lines 125,135,145.

### A7. `check_hashes` — P2 undefined colors
`GREEN`/`RED`/`NO_COLOR` used (188–191) but never defined. Define locally:
`local -r GREEN=$'\e[32m' RED=$'\e[31m' NO_COLOR=$'\e[0m'`.

### A8. `check_binary_contents*` — P2 sed path fragility
`other_dir=$(echo "$file" | sed "s/\/$2\//\/$3\//")` breaks on metachars. Replace
with zsh string ops: `other_dir="$1/$3/${file#$1/$2/}"` (strip known prefix, no
regex). Lines 225, 321.

### A9. Image funcs — P2 flags-by-argcount → `zparseopts` + P3 `convert`→`magick`
Rewrite `convert_png_to_jpg`, `batch_resize`, `batch_crop` to parse real flags
with `zparseopts` (mirrors the `open-partitions` rewrite), removing the
`$#`-counting branches and the `# REWRITE THIS FUNCTION` TODO.

- `convert_png_to_jpg [-r] [<quality>] <path>` — `-r` = recursive (`**/*.png`),
  else `*.png`. Quality optional. Explicit, no more "1 arg = dir, ignore quality".
- `batch_resize [-f] <dir> <percentage>` — `-f` = in-place, else write to
  `resized/${f:t}` (`mkdir -p resized`).
- `batch_crop [-f] <dir> <geometry>` — `-f` = in-place, else `cropped/${f:t}`.

**IM7/IM6 compat:** pick the binary once — `magick` if present, else `convert`
(`local -r im=${commands[magick]:-convert}`). Avoids breaking IM6 users while
preferring the non-deprecated `magick`. No new dependency added.

### A10. `iommu_groups` — P2 word-splitting robustness
`for g in $(find ...)` + unquoted `${d##*/}` → zsh globs:
`for g in /sys/kernel/iommu_groups/*(/N)` and quote expansions. sysfs has no
spaces today, but this is cleaner and safe.

### A11. P3 missing `local`
`jpg_name` (subsumed by A9 rewrite), `other_dir`/`segments_*` — add to `local`
declarations so they don't leak into the interactive shell.

## Workstream B — open-partitions veracrypt + parallel

Current `open-partitions` modes: password (default), `-k <keyfile>`, `-f/--fido2`.
Mapper name = `${i:t}` (device basename). No mount.

### B1. veracrypt mode
- New flag `-v` / `--veracrypt`. Mutually exclusive with `-k` and `-f/--fido2`
  (extend the existing conflict check).
- Prompt **password and PIM once**; reuse for every device.
- Unlock: `print -rn -- "$password" | cryptsetup --type tcrypt \`
  `--veracrypt-pim "$pim" open "$i" "${i:t}" -`
- `unset password pim` before returning (secret hygiene, like the old func).
- No mount — `open-partitions` only unlocks; caller mounts.

### B2. Refactor to a shared per-device unlock helper
Extract mode dispatch into a helper so sequential and parallel share one code
path. zsh `local`s are dynamically scoped, so the helper sees the caller's mode
vars (`o_fido`, `o_keyfile`, `o_vera`, `keyfile_loc`, `password`, `pim`):

```zsh
_open_partitions_unlock() {   # $1 = device; returns cryptsetup/systemd rc
    local dev="$1" dm="${1:t}"
    if [ -n "$o_fido" ]; then
        systemd-cryptsetup attach "$dm" "$dev" - fido2-device=auto
    elif [ -n "$o_keyfile" ]; then
        cryptsetup --key-file "$keyfile_loc" open "$dev" "$dm"
    elif [ -n "$o_vera" ]; then
        print -rn -- "$password" | cryptsetup --type tcrypt \
            --veracrypt-pim "$pim" open "$dev" "$dm" -
    else
        print -rn -- "$password" | cryptsetup open "$dev" "$dm" -
    fi
}
```

### B3. parallel mode (opt-in)
- New flag `-p` / `--parallel`. Default stays **sequential** (unchanged behavior
  and error-output ordering).
- Sequential (default): loop, call helper, `return 1` on first failure (current
  semantics).
- Parallel (`-p`): background each device, collect `pid → device`, `wait` each,
  set `rc=1` and print which device failed; attempt all, return non-zero if any
  failed.

```zsh
if [ -n "$o_parallel" ] && [ -z "$o_fido" ]; then
    local -a pids; local -A pid_dev; local rc=0 p
    for i in "$@"; do
        _open_partitions_unlock "$i" &
        pids+=($!); pid_dev[$!]="$i"
    done
    for p in "${pids[@]}"; do
        wait "$p" || { echo "Error: failed to unlock ${pid_dev[$p]}" >&2; rc=1; }
    done
    unset password pim
    return $rc
fi
# else sequential (existing loop, via helper)
```

- **FIDO2 + `-p`**: a single hardware token can't service concurrent touches, so
  FIDO2 always runs sequentially. If `-f` and `-p` are given together, print a
  warning to stderr and proceed sequentially (don't error out).
- Note: parallel argon2 KDF is RAM-heavy; fine for a handful of devices.

### B4. Usage text
Update the `open-partitions` usage banner to document `-v/--veracrypt`,
`-p/--parallel`, the new mutual-exclusions, and the FIDO2+parallel caveat.

## Testing (bats)

Extend `test/test_helper.bash` stubs (`cryptsetup`, `systemd-cryptsetup` already
there; add `magick`/`convert`, and for image tests run in a `mktemp -d`).

New/updated specs:
- `open-partitions.bats`: veracrypt mode emits
  `CS:--type tcrypt --veracrypt-pim <pim> open <dev> <basename> -`; `-v` conflicts
  with `-k` and `-f`; `-p` opens all devices (all appear in output, status 0);
  `-p` reports a failing device and returns non-zero (stub returns 1 for one
  device); `-f -p` warns and still attaches sequentially.
- `image.bats` (new): `convert_png_to_jpg`/`batch_resize`/`batch_crop` flag
  parsing, usage on no args, output path `resized/${f:t}` / `cropped/${f:t}`,
  recursive vs non-recursive glob, binary selection (`magick` preferred).
- `misc.bats` (new): `rand*` length + charset (stub-free, reads urandom);
  `check_hashes` uses a temp file (no `./aux` created); `create_random_files`
  usage/guard paths; `iommu_groups` runs without word-split errors (may skip if
  no `/sys/kernel/iommu_groups`).

Destructive/hardware cores (`open_mount_veracrypt` real unlock+mount,
`btrfs_*`, real `dd`) — arg-parsing/usage paths only, per project rules.

Run: `bats test/`. Lint: `shellcheck --shell=bash zsh-useful-functions.zsh`
(zsh-only constructs may warn; judge case-by-case).

## Risks / notes

- `check_binary_contents` prefix-strip (A8) assumes `$file` starts with
  `$1/$2/` — always true since `find "$1/$2"` produced it. Safe.
- `magick`/`convert` fallback keeps IM6 working; no new dependency.
- Parallel changes are gated behind `-p`; default path byte-identical in behavior.
- `open_mount_veracrypt` intentionally untouched beyond the `print -rn` fix.
