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
