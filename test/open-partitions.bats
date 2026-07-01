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
    run_op /dev/sda1 <<< "hunter2"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CS:open /dev/sda1 sda1 -"* ]]
}

@test "back-compat open_partitions forwards to open-partitions" {
    run_op_legacy -f /dev/sda1
    [ "$status" -eq 0 ]
    [[ "$output" == *"SC:attach sda1 /dev/sda1 - fido2-device=auto"* ]]
}
