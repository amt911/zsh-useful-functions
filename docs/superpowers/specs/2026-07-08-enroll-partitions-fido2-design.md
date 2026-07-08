# enroll-partitions — FIDO2 mass enrollment design

Date: 2026-07-08

## Purpose

Enroll a FIDO2 passkey into multiple LUKS/dm-crypt devices in one call, the same
way `open-partitions` unlocks many devices at once. For each device it announces
which partition is being touched, runs `systemd-cryptenroll`, then lists the
device's enrolled slots/tokens so the user can confirm the passkey landed.

## Signature

```
enroll-partitions [-h|--help] <device>...
```

- No flags → enroll a FIDO2 credential on every `<device>`.
- `-h/--help` → print the usage banner and `return 0`.
- `argc == 0` → print the usage banner and `return 1`.

The FIDO2 flags are fixed (not configurable), matching the user's canonical
command:

```
systemd-cryptenroll <dev> \
  --fido2-device=auto \
  --fido2-with-client-pin=yes \
  --fido2-with-user-presence=yes
```

## Behavior

Devices are processed **sequentially** — enrollment requires the physical FIDO2
token, so parallelism is not offered (mirrors how `open-partitions` refuses
`--parallel` in FIDO2 mode).

For each `<device>`:

1. Print a header to stdout announcing the device:
   `>>> Enrolling FIDO2 on <dev>`
2. Run `systemd-cryptenroll <dev> --fido2-device=auto --fido2-with-client-pin=yes --fido2-with-user-presence=yes`.
   `systemd-cryptenroll` prompts interactively for an existing passphrase/keyslot
   to authorize adding the new key.
3. On success → **verify**: run `systemd-cryptenroll <dev>` with no flags, which
   lists the device's registered keyslots/tokens, so the new FIDO2 token is
   visible for confirmation.
4. On failure (bad passphrase, token removed, non-LUKS device) → record the
   device in a `failed` list and continue to the next device.

## Error handling

Continue-and-report: a failing device never aborts the batch. After the loop, if
`failed` is non-empty, print `Failed: <dev> <dev> ...` to stderr and `return 1`;
otherwise `return 0`. The verify step's exit status is informational only — a
successful enroll followed by a noisy `list` still counts as success (but a
failed enroll skips its own verify).

## Structure & style

- Follows existing repo conventions: `zparseopts -D -E -F` (only `-h/--help`),
  `local -r` for constants, usage banner on `argc == 0` / `-h`, explicit
  `unset i` at end, explicit non-zero `return` codes.
- Helper `_enroll_partitions_one <dev>` performs the announce → enroll → verify
  for a single device and returns the enroll command's exit code (the same
  helper split used by `_open_partitions_unlock`). The verify runs only when the
  enroll succeeds; the helper's return code reflects the enroll, not the verify.
- Back-compat wrapper: `enroll_partitions() { enroll-partitions "$@"; }`
  (matches the `open_partitions` → `open-partitions` wrapper convention).

## Dependencies

No new external dependency: `systemd-cryptenroll` ships with systemd, already
assumed present alongside `systemd-cryptsetup` (used by `open-partitions`). Add
a mention to CLAUDE.md's dependency list only if the existing list would
otherwise be misleading.

## Testing (TDD, required)

New logic → red/green/refactor with bats. Interactive/destructive core
(`systemd-cryptenroll` against a real LUKS device) is covered on its
arg-parsing/usage paths and via a stub, not by faking real enrollment:

- **Usage**: no args → banner + rc 1; `-h`/`--help` → banner + rc 0.
- **Invalid option**: unknown flag → error + rc 1.
- **Happy path (stubbed `systemd-cryptenroll`)**: with a stub on PATH, assert
  for each device the header prints the device name, that enroll is invoked with
  the three fixed FIDO2 flags, and that the no-flag verify call runs **after**
  the enroll call (order assertion, like the readonly-before-writable order test
  in `mount_partitions`).
- **Failure aggregation**: stub returns non-zero for one device → that device
  appears in the `Failed:` summary, other devices still processed, function
  returns 1.
