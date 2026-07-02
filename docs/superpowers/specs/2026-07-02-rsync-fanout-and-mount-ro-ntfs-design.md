# rsync_fanout + mount_partitions readonly/NTFS — Design

Date: 2026-07-02

## Goal

Support a backup workflow: unlock VeraCrypt volumes (`open-partitions -v`), mount a
base source partition **readonly** and target volumes writable in a single command,
then `rsync` the base source to every target with a fixed set of excludes.

Current manual workflow being replaced:

```zsh
for i in "${veracrypt64[@]}"
do
  rsync -avcn --delete \
    --exclude "System Volume Information" \
    --exclude "\$RECYCLE.BIN" \
    --exclude "Versiones anteriores" \
    --exclude ".Trash-1000" \
    /mnt/nvme1n1p4/ /mnt/$i
done
```

## Part 1 — `mount_partitions`: per-device readonly + NTFS driver

Extend the existing `mount_partitions` (do not create a new function).

### New behavior

- **`-r <device>` (repeatable)** — marks a device to be mounted readonly. Writable
  devices remain positional args. Both readonly and writable devices are mounted in the
  same invocation.
  ```zsh
  mount_partitions -r /dev/nvme1n1p4 /dev/mapper/veracrypt1 /dev/mapper/veracrypt2
  #                 └── readonly ──┘  └────────── writable ───────────┘
  ```
  Multiple readonly: `-r /dev/a -r /dev/b /dev/c`.
- **NTFS detection** — per device, read the filesystem type with
  `lsblk -no FSTYPE <device>`. If it is `ntfs`, mount with the `ntfs-3g` driver;
  otherwise use the existing `mount --mkdir`.
- **`-b` / `--base`** — unchanged; applies to every device (readonly and writable).
- **`-h` / `--help`** — updated usage banner documenting `-r`.

### Per-device mount logic

```
target = base/<device-basename>
fstype = lsblk -no FSTYPE <device>      # first/only line for a leaf device

if fstype == "ntfs":
    mkdir -p target                     # ntfs-3g has no --mkdir
    ntfs-3g [-o ro] <device> target
else:
    mount [-o ro] --mkdir <device> target
```

`-o ro` is added only for devices passed via `-r`.

On any mount failure: print `Error: failed to mount <dev> at <target>` to stderr,
`unset` loop vars, `return 1` (matches existing behavior).

### Ordering

Readonly devices (from the `-r` list) are mounted first, then the writable positional
devices. Order within each group follows the argument order.

### New external dependency

`ntfs-3g` — deliberate addition (user requested it explicitly). Must be added to the
dependency list in `CLAUDE.md` and any README/help notes alongside the other CLIs.

## Part 2 — `rsync_fanout`: one source → many destinations

New function.

### Signature

```
rsync_fanout [-n] [-D] [-x <pattern>]... <source> <dest>...
```

- **`-n` / `--dry-run`** — add `--dry-run` to rsync (no changes made).
- **`-D` / `--delete`** — opt-in `--delete` (destructive; OFF by default, unlike the
  original manual command).
- **`-x <pattern>` / `--exclude <pattern>`** — repeatable; appended to the built-in
  excludes.
- **`-h` / `--help`** — usage banner.

### Built-in excludes (always applied)

- `System Volume Information`
- `$RECYCLE.BIN`
- `Versiones anteriores`
- `.Trash-1000`

### Behavior

- Base rsync flags always: `-avc`.
- Requires at least one `<source>` and one `<dest>`; otherwise usage error + `return 1`.
- Source and destination paths are passed **verbatim** (trailing slash on the source is
  significant to rsync and must be preserved — do not normalize).
- Loop rsync over each `<dest>`; abort on the first non-zero rsync exit (`return 1`),
  reporting which destination failed.

### Command built per destination

```
rsync -avc [--dry-run] [--delete] \
  --exclude "System Volume Information" \
  --exclude "$RECYCLE.BIN" \
  --exclude "Versiones anteriores" \
  --exclude ".Trash-1000" \
  [--exclude <extra>]... \
  <source> <dest>
```

## Testing (TDD, bats)

Stub `rsync`, `lsblk`, `mount`, `ntfs-3g` in the test helper to capture the argv they are
invoked with, then assert on the constructed command. New/changed function ⇒ at least one
happy-path and one usage-error test each.

### `mount_partitions`

- Usage error when no devices given / `--help` prints banner and returns 0.
- Writable device (non-ntfs) → `mount --mkdir <dev> <base>/<basename>` (no `-o ro`).
- `-r <dev>` (non-ntfs) → `mount -o ro --mkdir ...`.
- NTFS device (lsblk stub returns `ntfs`) → `mkdir -p` + `ntfs-3g` invoked; no plain
  `mount`.
- NTFS + `-r` → `ntfs-3g -o ro ...`.
- Mixed invocation: one `-r` readonly + one writable positional → both mounted, correct
  ro flag on each.
- `-b` changes the target base dir.
- Mount failure (stub returns non-zero) → `return 1`, error on stderr.

### `rsync_fanout`

- Usage error with zero args, and with source-but-no-dest.
- Default invocation builds `-avc` + all four built-in excludes, **no** `--delete`,
  **no** `--dry-run`.
- `-D` adds `--delete`; `-n` adds `--dry-run`.
- `-x foo -x bar` appends both as extra `--exclude` after the built-ins.
- Multiple dests → rsync invoked once per dest with the same flags.
- Source trailing slash preserved verbatim.
- First rsync failure aborts the loop with `return 1`.

## Style constraints (from CLAUDE.md)

- `zparseopts -D -E -F` for option parsing (as in `mount_partitions` / `open-partitions`).
- `local -r` for constants, explicit `unset` of loop vars at end of each function.
- `[ ]`-style POSIX tests, usage banner on `argc == 0` or invalid input, explicit
  non-zero `return` codes.
- No credential handling in either function (nothing to `unset` for secrets here).
```