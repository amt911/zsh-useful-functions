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
