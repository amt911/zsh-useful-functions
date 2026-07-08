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
