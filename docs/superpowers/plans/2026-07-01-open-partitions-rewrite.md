# open-partitions Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite the LUKS/dm-crypt unlock helper as `open-partitions` with a fixed passphrase feed, robust `zparseopts` parsing, FIDO2 support, a back-compat wrapper, and a bats test suite.

**Architecture:** Single zsh function in `zsh-useful-functions.zsh`. Three unlock modes (password / keyfile / FIDO2) selected by flags parsed with `zparseopts -D -F`. Mapper name derived from the device's last path component (`${dev:t}`). Tests run under bats-core (vendored as a git submodule); the real function is exercised in a fresh `zsh -c` subshell with `cryptsetup` / `systemd-cryptsetup` replaced by stub functions, so no real crypto runs.

**Tech Stack:** zsh (`zparseopts`, `${var:t}`, `print -rn`), cryptsetup, systemd-cryptsetup, bats-core.

## Global Constraints

- Target shell is zsh; zsh-specific syntax is expected (`${var:t}`, `zparseopts`, `local -r`).
- Preserve existing style: `local -r` for constants, usage banner on `argc == 0` / invalid flags, explicit non-zero `return` codes, `unset` of loop variables at end.
- Secret handling: read password once with `read -rs`; `unset password` on every return path (CLAUDE.md).
- No new runtime tool dependency beyond `systemd-cryptsetup` (part of systemd, already present on the target Arch box).
- `-k` and `-f`/`--fido2` are mutually exclusive.
- Mapper name = last path component of the device (`${dev:t}`), so `/dev/disk/by-uuid/<uuid>` → `/dev/mapper/<uuid>`.
- Bug #2 fix = feed passphrase with `print -rn -- "$password"` (no trailing newline), NOT `echo`. The real-crypto happy path is verified manually by the author (hardware-dependent).

---

### Task 1: Vendor bats-core and scaffold the test harness

**Files:**
- Create: `.gitmodules` (via `git submodule add`)
- Create: `test/bats/` (submodule checkout)
- Create: `test/test_helper.bash`
- Create: `test/smoke.bats`

**Interfaces:**
- Produces: `bats` runnable via `./test/bats/bin/bats test/`; helper `run_op` (defined in `test_helper.bash`) that runs `open-partitions` in a stubbed `zsh -c` subshell.
- Consumes: nothing.

- [ ] **Step 1: Add bats-core as a submodule**

Run:
```bash
git submodule add https://github.com/bats-core/bats-core.git test/bats
```
Expected: `test/bats/bin/bats` exists.
Fallback if the network is unavailable: `sudo pacman -S bats` and skip the submodule; in that case invoke tests with `bats test/` instead of `./test/bats/bin/bats test/`.

- [ ] **Step 2: Write the test helper**

Create `test/test_helper.bash`:
```bash
# Absolute path to the plugin file under test.
PLUGIN_FILE="${BATS_TEST_DIRNAME}/../zsh-useful-functions.zsh"

# Run open-partitions (or any snippet) in a fresh zsh with cryptsetup and
# systemd-cryptsetup replaced by stubs that echo their args and succeed.
# Usage: run_op <args...>            # runs: open-partitions <args...>
# Stdin (if any) is forwarded to the subshell for password-mode tests.
run_op() {
    run zsh -c '
        cryptsetup(){ print "CS:$*"; return 0; }
        systemd-cryptsetup(){ print "SC:$*"; return 0; }
        source "$1"
        shift
        open-partitions "$@"
    ' _ "$PLUGIN_FILE" "$@"
}

# Same as run_op but calls the back-compat name open_partitions.
run_op_legacy() {
    run zsh -c '
        cryptsetup(){ print "CS:$*"; return 0; }
        systemd-cryptsetup(){ print "SC:$*"; return 0; }
        source "$1"
        shift
        open_partitions "$@"
    ' _ "$PLUGIN_FILE" "$@"
}
```

- [ ] **Step 3: Write a smoke test**

Create `test/smoke.bats`:
```bash
load test_helper

@test "plugin file sources cleanly in zsh" {
    run zsh -c 'source "$1"' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 4: Run the smoke test to verify the harness works**

Run: `./test/bats/bin/bats test/smoke.bats`
Expected: 1 test, PASS.

- [ ] **Step 5: Commit**

```bash
git add .gitmodules test/bats test/test_helper.bash test/smoke.bats
git commit -m "Add bats-core submodule and test harness

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: TDD the `open-partitions` rewrite

**Files:**
- Create: `test/open-partitions.bats`
- Modify: `zsh-useful-functions.zsh` (replace the `open_partitions` function, lines 424-480, and add the new function + wrapper)

**Interfaces:**
- Consumes: `run_op` / `run_op_legacy` from `test/test_helper.bash`.
- Produces:
  - `open-partitions [-k <keyfile> | -f | --fido2] <device>...` — unlocks each device; returns 1 on usage error, bad flag, mode conflict, or any cryptsetup/systemd-cryptsetup failure.
  - `open_partitions` — back-compat wrapper forwarding all args to `open-partitions`.
  - Mapper name for each device is `${device:t}`.
  - Command shapes (as observed via stubs):
    - keyfile: `CS:--key-file <keyfile> open <device> <name>`
    - fido2:   `SC:attach <name> <device> - fido2-device=auto`
    - password: `CS:open <device> <name> -`

- [ ] **Step 1: Write the failing tests**

Create `test/open-partitions.bats`:
```bash
load test_helper

@test "no args prints usage and returns 1" {
    run_op
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: open-partitions"* ]]
}

@test "-h prints usage and returns 0" {
    run_op -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: open-partitions"* ]]
}

@test "-k and -f together is a conflict error" {
    run_op -k /root/key -f /dev/sda1
    [ "$status" -eq 1 ]
    [[ "$output" == *"mutually exclusive"* ]]
}

@test "unknown flag returns 1" {
    run_op -x /dev/sda1
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid option"* ]]
}

@test "keyfile mode derives mapper name from by-uuid path" {
    run_op -k /root/key /dev/disk/by-uuid/UUID
    [ "$status" -eq 0 ]
    [[ "$output" == *"CS:--key-file /root/key open /dev/disk/by-uuid/UUID UUID"* ]]
}

@test "fido2 mode uses systemd-cryptsetup attach" {
    run_op -f /dev/nvme1n1p1
    [ "$status" -eq 0 ]
    [[ "$output" == *"SC:attach nvme1n1p1 /dev/nvme1n1p1 - fido2-device=auto"* ]]
}

@test "--fido2 unlocks multiple devices" {
    run_op --fido2 /dev/nvme1n1p1 /dev/nvme1n1p2
    [ "$status" -eq 0 ]
    [[ "$output" == *"SC:attach nvme1n1p1 /dev/nvme1n1p1 - fido2-device=auto"* ]]
    [[ "$output" == *"SC:attach nvme1n1p2 /dev/nvme1n1p2 - fido2-device=auto"* ]]
}

@test "password mode reads passphrase and opens device" {
    echo "hunter2" | run_op /dev/sda1
    [ "$status" -eq 0 ]
    [[ "$output" == *"CS:open /dev/sda1 sda1 -"* ]]
}

@test "back-compat open_partitions forwards to open-partitions" {
    run_op_legacy -f /dev/sda1
    [ "$status" -eq 0 ]
    [[ "$output" == *"SC:attach sda1 /dev/sda1 - fido2-device=auto"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./test/bats/bin/bats test/open-partitions.bats`
Expected: FAIL — the current file defines `open_partitions` (underscore) with old behavior and no `open-partitions`, so most cases error (`command not found: open-partitions`) or mismatch on output.

- [ ] **Step 3: Replace the function in the plugin file**

In `zsh-useful-functions.zsh`, delete the entire existing `open_partitions()` block (currently lines 424-480) and replace it with:

```zsh
# Opens (unlocks) one or more LUKS/dm-crypt devices.
# Modes: password (default), keyfile (-k <file>), FIDO2 (-f / --fido2).
# The mapper name is the last path component of each device (${dev:t}),
# so /dev/disk/by-uuid/<uuid> maps to /dev/mapper/<uuid>.
open-partitions(){
    local -a o_keyfile o_fido o_help
    zparseopts -D -F -- k:=o_keyfile f=o_fido -fido2=o_fido h=o_help -help=o_help 2>/dev/null
    local -r parse_rc=$?

    if [ "$parse_rc" -ne "0" ];
    then
        echo "Error: invalid option" >&2
        return 1
    fi

    if [ -n "$o_help" ] || [ "$#" -eq "0" ];
    then
        echo "Usage: open-partitions [-k <keyfile> | -f | --fido2] <device>..."
        echo "  (no flag)      password mode  — prompt once, unlock every device"
        echo "  -k <keyfile>   keyfile mode   — cryptsetup --key-file <keyfile>"
        echo "  -f, --fido2    FIDO2 mode     — systemd-cryptsetup attach ... fido2-device=auto"
        echo "  -h, --help     show this help"
        [ -n "$o_help" ] && return 0
        return 1
    fi

    if [ -n "$o_keyfile" ] && [ -n "$o_fido" ];
    then
        echo "Error: -k and -f/--fido2 are mutually exclusive" >&2
        return 1
    fi

    local -r keyfile_loc="${o_keyfile[2]}"

    local password=""
    if [ -z "$o_keyfile" ] && [ -z "$o_fido" ];
    then
        echo -n "Password: "
        read -rs password
        echo
    fi

    local i dm_name
    for i in "$@"
    do
        # Mapper name = last path component; robust for /dev/disk/by-uuid/... paths.
        dm_name="${i:t}"

        if [ -n "$o_fido" ];
        then
            systemd-cryptsetup attach "$dm_name" "$i" - fido2-device=auto
        elif [ -n "$o_keyfile" ];
        then
            cryptsetup --key-file "$keyfile_loc" open "$i" "$dm_name"
        else
            # print -rn (no trailing newline, no escapes) — feeding with echo
            # appends "\n" and cryptsetup rejects it as "No key available".
            print -rn -- "$password" | cryptsetup open "$i" "$dm_name" -
        fi

        if [ "$?" -ne "0" ];
        then
            unset i dm_name password
            return 1
        fi
    done
    unset i dm_name

    # Unsets password to avoid a leak
    unset password
}


# Back-compat wrapper for the previous underscore name.
open_partitions(){
    open-partitions "$@"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./test/bats/bin/bats test/open-partitions.bats`
Expected: 9 tests, all PASS.

- [ ] **Step 5: Lint the changed function**

Run: `shellcheck --shell=bash zsh-useful-functions.zsh || true`
Expected: no NEW errors attributable to the rewritten function beyond the pre-existing shellcheck noise in the file (shellcheck has no zsh dialect; `${i:t}`, `zparseopts`, and `print` may draw warnings — these are acceptable for this zsh-only file). Do not "fix" zsh-specific constructs to satisfy shellcheck.

- [ ] **Step 6: Commit**

```bash
git add zsh-useful-functions.zsh test/open-partitions.bats
git commit -m "Rewrite open_partitions as open-partitions with FIDO2 and passphrase fix

- Rename to open-partitions; keep open_partitions as back-compat wrapper
- Fix password mode: feed passphrase with 'print -rn --' instead of echo,
  which appended a newline and caused 'No key available with this passphrase'
- Parse args with zparseopts -D -F (strict unknown-flag handling)
- Add FIDO2 mode via systemd-cryptsetup attach (-f / --fido2)
- Derive mapper name from \${dev:t} so /dev/disk/by-uuid/<uuid> works
- Add bats tests covering usage, flag conflict, dispatch, and dm_name

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Manual verification (author, real hardware)

Automated tests stub the crypto. Before merging, the author verifies the real
paths on an actual LUKS2 device:

- Password mode on a single device: `open-partitions /dev/<luks-part>` unlocks
  without `No key available with this passphrase` (the bug #2 regression check).
- FIDO2 mode: `open-partitions -f /dev/<luks-part>` unlocks via the Thetis key
  (`systemd-cryptenroll <dev>` must list a `fido2` slot first — see the guide).
- Keyfile mode unchanged: `open-partitions -k <keyfile> /dev/<luks-part>`.
- `close_partitions <name>` closes each opened mapper.

## Notes for the audit deliverable (separate, after this task)

The whole-file audit is report-only and NOT part of this plan's tasks. Deliver
it as a written report after Task 2 is merged-ready.
