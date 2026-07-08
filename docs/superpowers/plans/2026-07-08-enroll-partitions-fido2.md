# enroll-partitions FIDO2 Mass Enrollment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an `enroll-partitions` shell function that enrolls a FIDO2 passkey into multiple LUKS devices in one call, announcing each device and listing its slots afterward for confirmation.

**Architecture:** A helper `_enroll_partitions_one <dev>` announces the device, runs `systemd-cryptenroll` with fixed FIDO2 flags, and — only on enroll success — runs a no-flag `systemd-cryptenroll <dev>` to list slots. The public `enroll-partitions` parses `-h/--help`, loops devices sequentially, aggregates failures, and returns non-zero if any device failed. A `enroll_partitions` wrapper preserves the underscore-name convention.

**Tech Stack:** zsh, `systemd-cryptenroll` (systemd), bats-core for tests.

## Global Constraints

- Target shell: `#!/bin/zsh`; use `zparseopts -D -E -F`, `local -r`, `[ ]`-style POSIX tests, explicit `unset` of loop vars, explicit non-zero `return` codes — match existing `open-partitions`.
- No new external tool dependency: `systemd-cryptenroll` ships with systemd (already assumed alongside `systemd-cryptsetup`).
- FIDO2 flags are FIXED, verbatim: `--fido2-device=auto --fido2-with-client-pin=yes --fido2-with-user-presence=yes`.
- Devices processed sequentially (FIDO2 needs the physical token) — no `--parallel`.
- Tests: bats-core, run with `./test/bats/bin/bats test/`. Every new function needs ≥1 happy-path and ≥1 usage-error test.

---

## File Structure

- **Modify:** `zsh-useful-functions.zsh` — add `_enroll_partitions_one`, `enroll-partitions`, `enroll_partitions` near `open-partitions` (after `close_partitions`, ~line 850).
- **Modify:** `test/test_helper.bash` — add a `run_enroll` helper that stubs `systemd-cryptenroll`.
- **Create:** `test/enroll-partitions.bats` — the spec's test cases.
- **Modify:** `CLAUDE.md` — add `systemd-cryptenroll` to the external-dependency list.

---

### Task 1: Test helper + usage/arg-parsing skeleton

**Files:**
- Modify: `test/test_helper.bash` (append a helper)
- Create: `test/enroll-partitions.bats`
- Modify: `zsh-useful-functions.zsh` (add skeleton `enroll-partitions`)

**Interfaces:**
- Consumes: `PLUGIN_FILE` (already defined in `test_helper.bash`), `run` from bats.
- Produces: shell function `enroll-partitions [-h|--help] <device>...`; bash helper `run_enroll [ENROLL_FAIL=<substr>] <args...>` that stubs `systemd-cryptenroll` (prints `CE:$*` and succeeds, or returns 1 when its args contain the `ENROLL_FAIL` substring together with `--fido2-device`).

- [ ] **Step 1: Add the `run_enroll` helper to `test/test_helper.bash`**

Append to `test/test_helper.bash`:

```bash
# Run enroll-partitions in a fresh zsh with systemd-cryptenroll stubbed.
# The stub prints "CE:<args>" and succeeds. If the environment variable
# ENROLL_FAIL is set and BOTH it and "--fido2-device" appear in the args, the
# stub returns 1 — this fails the *enroll* call (which carries the fido2 flags)
# for the named device while leaving the no-flag verify call succeeding.
# Usage: run_enroll <args...>            # ENROLL_FAIL passed via `ENROLL_FAIL=... run_enroll ...`
run_enroll() {
    run zsh -c '
        systemd-cryptenroll(){
            if [ -n "$ENROLL_FAIL" ] && [[ "$*" == *"$ENROLL_FAIL"* ]] && [[ "$*" == *"--fido2-device"* ]]; then
                return 1
            fi
            print "CE:$*"
            return 0
        }
        source "$1"
        shift
        enroll-partitions "$@"
    ' _ "$PLUGIN_FILE" "$@"
}
```

- [ ] **Step 2: Write the failing usage tests in `test/enroll-partitions.bats`**

Create `test/enroll-partitions.bats`:

```bash
load test_helper

@test "no args prints usage and returns 1" {
    run_enroll
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: enroll-partitions"* ]]
}

@test "-h prints usage and returns 0" {
    run_enroll -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: enroll-partitions"* ]]
}

@test "--help prints usage and returns 0" {
    run_enroll --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: enroll-partitions"* ]]
}

@test "unknown flag returns 1" {
    run_enroll -x /dev/sda1
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid option"* ]]
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `./test/bats/bin/bats test/enroll-partitions.bats`
Expected: FAIL — `enroll-partitions: command not found` (function not defined yet).

- [ ] **Step 4: Add the skeleton function to `zsh-useful-functions.zsh`**

Insert after the `close_partitions` function (end of file, ~line 850):

```zsh


# Enrolls a FIDO2 passkey into one or more LUKS/dm-crypt devices, sequentially.
# For each device it announces which partition is touched, runs
# systemd-cryptenroll with fixed FIDO2 flags (device=auto, client-pin=yes,
# user-presence=yes), then lists the device's slots/tokens so the new key can
# be confirmed. A failing device does not abort the batch; failures are
# reported at the end and the function returns 1 if any occurred.
enroll-partitions(){
    local -a o_help
    zparseopts -D -E -F -- h=o_help -help=o_help 2>/dev/null
    local -r parse_rc=$?

    if [ "$parse_rc" -ne "0" ];
    then
        echo "Error: invalid option" >&2
        return 1
    fi

    if [ -n "$o_help" ] || [ "$#" -eq "0" ];
    then
        echo "Usage: enroll-partitions [-h|--help] <device>..."
        echo "  Enrolls a FIDO2 passkey into each LUKS device (sequential)."
        echo "  Fixed flags: --fido2-device=auto --fido2-with-client-pin=yes --fido2-with-user-presence=yes"
        echo "  systemd-cryptenroll prompts for an existing passphrase to authorize each device."
        echo "  -h, --help     show this help"
        [ -n "$o_help" ] && return 0
        return 1
    fi

    return 0
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `./test/bats/bin/bats test/enroll-partitions.bats`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add test/test_helper.bash test/enroll-partitions.bats zsh-useful-functions.zsh
git commit -m "test: enroll-partitions usage/arg-parsing + run_enroll helper"
```

---

### Task 2: Per-device enroll + verify + failure aggregation

**Files:**
- Modify: `zsh-useful-functions.zsh` (add `_enroll_partitions_one`, fill in the loop, add `enroll_partitions` wrapper)
- Modify: `test/enroll-partitions.bats` (add behavior tests)

**Interfaces:**
- Consumes: `enroll-partitions` skeleton and `run_enroll` from Task 1.
- Produces: helper `_enroll_partitions_one <dev>` (announces, enrolls, verifies on success; returns the enroll exit code); wrapper `enroll_partitions() { enroll-partitions "$@"; }`.

- [ ] **Step 1: Write the failing behavior tests**

Append to `test/enroll-partitions.bats`:

```bash
@test "announces the device before enrolling" {
    run_enroll /dev/sda3
    [ "$status" -eq 0 ]
    [[ "$output" == *">>> Enrolling FIDO2 on /dev/sda3"* ]]
}

@test "enroll uses the three fixed fido2 flags" {
    run_enroll /dev/sda3
    [ "$status" -eq 0 ]
    [[ "$output" == *"CE:/dev/sda3 --fido2-device=auto --fido2-with-client-pin=yes --fido2-with-user-presence=yes"* ]]
}

@test "verify (no-flag list) runs after enroll for the device" {
    run_enroll /dev/sda3
    [ "$status" -eq 0 ]
    # The enroll line (with flags) must appear before the bare verify line.
    enroll_line=$(printf '%s\n' "$output" | grep -n 'CE:/dev/sda3 --fido2-device' | head -1 | cut -d: -f1)
    verify_line=$(printf '%s\n' "$output" | grep -n 'CE:/dev/sda3$' | head -1 | cut -d: -f1)
    [ -n "$enroll_line" ]
    [ -n "$verify_line" ]
    [ "$enroll_line" -lt "$verify_line" ]
}

@test "enrolls multiple devices sequentially" {
    run_enroll /dev/sda3 /dev/sdb3
    [ "$status" -eq 0 ]
    [[ "$output" == *">>> Enrolling FIDO2 on /dev/sda3"* ]]
    [[ "$output" == *">>> Enrolling FIDO2 on /dev/sdb3"* ]]
    [[ "$output" == *"CE:/dev/sda3 --fido2-device=auto"* ]]
    [[ "$output" == *"CE:/dev/sdb3 --fido2-device=auto"* ]]
}

@test "a failing device is reported and does not abort the batch" {
    ENROLL_FAIL=/dev/sda3 run_enroll /dev/sda3 /dev/sdb3
    [ "$status" -eq 1 ]
    # sdb3 still processed
    [[ "$output" == *"CE:/dev/sdb3 --fido2-device=auto"* ]]
    # sda3 listed as failed
    [[ "$output" == *"Failed:"* ]]
    [[ "$output" == *"/dev/sda3"* ]]
}

@test "no failure summary when all succeed" {
    run_enroll /dev/sda3
    [[ "$output" != *"Failed:"* ]]
}

@test "back-compat enroll_partitions delegates to enroll-partitions" {
    run zsh -c '
        systemd-cryptenroll(){ print "CE:$*"; return 0; }
        source "$1"; shift
        enroll_partitions "$@"
    ' _ "$PLUGIN_FILE" /dev/sda3
    [ "$status" -eq 0 ]
    [[ "$output" == *">>> Enrolling FIDO2 on /dev/sda3"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./test/bats/bin/bats test/enroll-partitions.bats`
Expected: FAIL — no announce output, no `CE:` enroll line, `enroll_partitions` not found.

- [ ] **Step 3: Add the `_enroll_partitions_one` helper**

Insert in `zsh-useful-functions.zsh` immediately **before** the `enroll-partitions` function added in Task 1:

```zsh
# Enroll a FIDO2 passkey into a single device, then list its slots to confirm.
# Announces the device first. Runs systemd-cryptenroll with the fixed FIDO2
# flags; on success runs the no-flag list. Returns the enroll exit code (the
# verify/list status is informational only).
_enroll_partitions_one() {
    local -r dev="$1"

    echo ">>> Enrolling FIDO2 on $dev"
    if systemd-cryptenroll "$dev" --fido2-device=auto --fido2-with-client-pin=yes --fido2-with-user-presence=yes;
    then
        systemd-cryptenroll "$dev"
        return 0
    fi
    return 1
}
```

- [ ] **Step 4: Fill in the loop in `enroll-partitions`**

In `zsh-useful-functions.zsh`, replace the trailing `return 0` of `enroll-partitions` (the line before its closing `}`) with:

```zsh
    local -a failed
    local i
    for i in "$@"
    do
        if ! _enroll_partitions_one "$i";
        then
            failed+=("$i")
        fi
    done
    unset i

    if [ "${#failed[@]}" -ne "0" ];
    then
        echo "Failed: ${failed[*]}" >&2
        return 1
    fi
    return 0
```

- [ ] **Step 5: Add the back-compat wrapper**

Insert after the `enroll-partitions` closing `}`:

```zsh


# Back-compat wrapper for the underscore name convention.
enroll_partitions(){
    enroll-partitions "$@"
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `./test/bats/bin/bats test/enroll-partitions.bats`
Expected: PASS (all tests — 4 from Task 1 + 7 new).

- [ ] **Step 7: Run the full suite to check for regressions**

Run: `./test/bats/bin/bats test/`
Expected: PASS (all files).

- [ ] **Step 8: Commit**

```bash
git add zsh-useful-functions.zsh test/enroll-partitions.bats
git commit -m "feat: add enroll-partitions for FIDO2 mass enrollment"
```

---

### Task 3: Documentation

**Files:**
- Modify: `CLAUDE.md` (dependency list)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing (docs only).

- [ ] **Step 1: Add `systemd-cryptenroll` to the dependency list in `CLAUDE.md`**

In `CLAUDE.md`, find the "External CLI dependencies" bullet in the Stack section. It currently reads (in part):

```
  `cryptsetup`, `systemd-cryptsetup`, `lspci`, ...
```

Change `systemd-cryptsetup` to `systemd-cryptsetup`, `systemd-cryptenroll` so the FIDO2 enrollment tool is listed:

```
  `cryptsetup`, `systemd-cryptsetup`, `systemd-cryptenroll`, `lspci`, ...
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: note systemd-cryptenroll dep for enroll-partitions"
```

---

## Self-Review

**Spec coverage:**
- Signature `enroll-partitions [-h|--help] <device>...` → Task 1 skeleton. ✓
- Fixed FIDO2 flags → Task 2 helper + test. ✓
- Announce header `>>> Enrolling FIDO2 on <dev>` → Task 2. ✓
- Verify via no-flag `systemd-cryptenroll <dev>` after enroll → Task 2 helper + order test. ✓
- Continue-and-report, `Failed:` to stderr, return 1 → Task 2 loop + test. ✓
- Sequential (no parallel) → loop has no `&`. ✓
- `_enroll_partitions_one` helper, `enroll_partitions` wrapper → Task 2. ✓
- Style (`local -r`, zparseopts, `unset i`, POSIX tests) → Task 1/2 code. ✓
- Dependency mention → Task 3. ✓
- Tests: usage/`-h`, invalid option, happy-path with header + flags, verify-order, failure aggregation → Tasks 1–2. ✓

**Placeholder scan:** No TBD/TODO; all code and commands are concrete. ✓

**Type consistency:** `_enroll_partitions_one`, `enroll-partitions`, `enroll_partitions`, `run_enroll`, `ENROLL_FAIL`, output markers `CE:` and `>>> Enrolling FIDO2 on` used identically across tasks. ✓
