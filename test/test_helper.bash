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
