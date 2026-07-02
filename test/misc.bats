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

@test "check_binary_contents_cmp finds the mirrored file (path rewrite)" {
    cd "$BATS_TEST_TMPDIR"
    mkdir -p root/a/sub root/b/sub
    printf 'same' > root/a/sub/f.bin
    printf 'same' > root/b/sub/f.bin
    run_plugin check_binary_contents_cmp root a b
    [ "$status" -eq 0 ]
    [[ "$output" == *"Both files are the same"* ]]
    [[ "$output" != *"does not exist"* ]]
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

@test "create_random_files rejects max < min" {
    run zsh -c 'source "$1"; create_random_files 1 5 2 "$2"' _ "$PLUGIN_FILE" "$BATS_TEST_TMPDIR"
    [ "$status" -ne 0 ]
    [[ "$output" == *"max-size"* ]]
}

@test "create_random_files with no args prints usage" {
    run zsh -c 'source "$1"; create_random_files' _ "$PLUGIN_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: create_random_files"* ]]
}

@test "check_hashes does not clobber ./aux" {
    cd "$BATS_TEST_TMPDIR"
    printf 'PRECIOUS' > aux
    printf 'deadbeef  file1\n' > h1
    printf 'deadbeef  file1\n' > h2
    run_plugin check_hashes h1 h2
    [ "$status" -eq 0 ]
    [ "$(cat aux)" = "PRECIOUS" ]
    [[ "$output" == *"OK"* ]]
}

@test "check_hashes with wrong arg count prints usage" {
    run zsh -c 'source "$1"; check_hashes onlyone' _ "$PLUGIN_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: check_hashes"* ]]
}

@test "iommu_groups runs without word-split errors" {
    if [ ! -d /sys/kernel/iommu_groups ]; then
        skip "no /sys/kernel/iommu_groups on this machine"
    fi
    run zsh -c 'source "$1"; iommu_groups' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
}
