# Design: `open-partitions` rewrite

Date: 2026-07-01

## Goal

Rewrite the `open_partitions` LUKS/dm-crypt unlock helper in
`zsh-useful-functions.zsh` to fix a passphrase bug, harden argument parsing,
add FIDO2 unlocking, and rename it to `open-partitions` (hyphen) while keeping
backward compatibility.

## Requirements

1. Rename `open_partitions` → `open-partitions` (hyphen, not underscore).
   Keep `open_partitions` as a back-compat wrapper.
2. Fix: opening a single partition in password mode fails with
   `No key available with this passphrase` even when the password is correct.
3. More robust argument parsing (use a real parser).
4. Add FIDO2 unlocking (per `guia_arch_luks_fido2_thetis_dracut_systemd_boot.md`).

## Root cause — bug #2

The current password path pipes the passphrase with:

```zsh
echo "$password" | cryptsetup open "$i" "$dm_name" -
```

`echo` appends a trailing newline, so cryptsetup receives `password\n` as the
key material. Depending on cryptsetup version / stdin handling this yields
`No key available with this passphrase` despite a correct password. The
"single partition" framing is incidental — the defect is in password mode
generally.

**Fix:** feed the passphrase with no trailing newline and no escape
interpretation:

```zsh
print -rn -- "$password" | cryptsetup open "$i" "$dm_name" -
```

This fix touches real LUKS hardware, so it is verified manually by the author,
not by an automated test.

## Secondary robustness fix — mapper name

Current code derives the mapper name with `cut -d/ -f3`, which breaks on paths
like `/dev/disk/by-uuid/<uuid>` (yields `by-uuid` instead of the uuid).
Replace with the zsh tail modifier:

```zsh
local -r dm_name="${i:t}"   # last path component
```

## Interface

```
open-partitions [-k <keyfile> | -f | --fido2] <device>...

  (no flag)        password mode  — prompt once, feed every device
  -k <keyfile>     keyfile mode   — cryptsetup --key-file <keyfile>
  -f | --fido2     FIDO2 mode     — systemd-cryptsetup attach (guide §16)
  -h | --help      usage banner

open_partitions   → back-compat wrapper: `open_partitions() { open-partitions "$@" }`
```

`-k` and `-f` are mutually exclusive → usage error. No devices → usage banner
and non-zero return.

## Parsing

Use zsh-native `zparseopts`:

```zsh
local -a o_keyfile o_fido o_help
zparseopts -D -E -F -- k:=o_keyfile f=o_fido -fido2=o_fido h=o_help -help=o_help
```

- `-D` removes parsed options from the positional list.
- `-E` keeps parsing tolerant of interleaved args (a flag appearing after a
  device is still parsed, not silently swallowed as a device path). Without it,
  `open-partitions /dev/x -k key` would treat `-k` as a device and bypass the
  `-k`/`-f` conflict check.
- `-F` rejects unknown flags (returns non-zero) instead of leaving them in the
  positional list. `-E` and `-F` compose: interleaved-tolerant AND strict.
- After parsing, `$@` holds the device list.

Validation:
- both `o_keyfile` and `o_fido` set → error, return 1.
- `o_help` set or `$#` == 0 → usage banner, return (0 for `-h`, 1 for no args).

## Per-device dispatch

```zsh
for i in "$@"; do
    local -r dm_name="${i:t}"
    case "$mode" in
        password) print -rn -- "$password" | cryptsetup open "$i" "$dm_name" - ;;
        keyfile)  cryptsetup --key-file "$keyfile_loc" open "$i" "$dm_name" ;;
        fido2)    systemd-cryptsetup attach "$dm_name" "$i" - fido2-device=auto ;;
    esac
    [ "$?" -ne 0 ] && { unset i password; return 1; }
done
unset i
unset password
```

FIDO2 command follows guide §16:
`systemd-cryptsetup attach <name> <device> - fido2-device=auto`.

## Secret handling

Per CLAUDE.md: password is read once with `read -rs`, and `unset password` on
every return path (success and failure). No password is read in keyfile or
FIDO2 mode.

## Style constraints (preserve existing conventions)

- `local -r` for constants.
- Usage banner printed on `argc == 0` or invalid flags.
- Explicit non-zero `return` codes.
- `unset` loop variable `i` at the end.
- POSIX `[ ]` tests where they already fit.

## Testing

CLAUDE.md mandates TDD via bats-core, not yet set up. This change introduces it.

- Add `test/open-partitions.bats`.
- Stub `cryptsetup` / `systemd-cryptsetup` as shell functions that echo their
  args and return 0, so arg-parsing and dispatch logic run against the real
  function (test-over-mock).
- Cases:
  - no args → usage banner, exit 1.
  - `-h` → usage banner, exit 0.
  - `-k f -f` → conflict error, exit 1.
  - dm_name derivation: `/dev/disk/by-uuid/UUID` → mapper name `UUID`
    (guards the `${i:t}` fix).
  - keyfile mode calls `cryptsetup --key-file <f> open <dev> <name>`.
  - fido2 mode calls `systemd-cryptsetup attach <name> <dev> - fido2-device=auto`.
- Destructive/real-crypto happy path stays manual (hardware-dependent
  exception in CLAUDE.md).

Coverage: happy-path + usage-error per the CLAUDE.md target for new work.

## Out of scope

- Full-file audit of the other functions is delivered as a **separate written
  report** (report-only, no code changes) after this rewrite.
- No new external tool dependency beyond `systemd-cryptsetup` (part of systemd,
  already assumed present on the target Arch system).
