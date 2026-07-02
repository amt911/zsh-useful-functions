load test_helper

@test "check_binary_contents preserves IFS" {
    cd "$BATS_TEST_TMPDIR"
    mkdir -p root/a/sub root/b/sub
    printf 'same' > root/a/sub/f.bin
    printf 'same' > root/b/sub/f.bin
    run zsh -c '
        source "$1"; shift
        before=$IFS
        check_binary_contents "$@" >/dev/null
        [ "$IFS" = "$before" ] && print "IFS-OK"
    ' _ "$PLUGIN_FILE" root a b
    [ "$status" -eq 0 ]
    [[ "$output" == *"IFS-OK"* ]]
}

@test "check_binary_contents finds the mirrored file (path rewrite)" {
    cd "$BATS_TEST_TMPDIR"
    mkdir -p root/a/sub root/b/sub
    printf 'same' > root/a/sub/f.bin
    printf 'same' > root/b/sub/f.bin
    run_plugin check_binary_contents root a b
    [ "$status" -eq 0 ]
    [[ "$output" == *"Both files are the same"* ]]
    [[ "$output" != *"does not exist on b"* ]]
}

@test "rand honors requested length and charset" {
    run zsh -c 'source "$1"; rand 12' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [ "${#output}" -eq 12 ]
    [[ "$output" =~ ^[a-zA-Z0-9]+$ ]]
}

@test "rand_num returns only digits" {
    run zsh -c 'source "$1"; rand_num 8' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [ "${#output}" -eq 8 ]
    [[ "$output" =~ ^[0-9]+$ ]]
}

@test "rand_letters returns only letters" {
    run zsh -c 'source "$1"; rand_letters 8' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [ "${#output}" -eq 8 ]
    [[ "$output" =~ ^[a-zA-Z]+$ ]]
}
