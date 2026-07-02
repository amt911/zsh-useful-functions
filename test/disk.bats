load test_helper

# lsblk stub emitting NAME SIZE TYPE rows (bytes). One disk + four partitions.
# 512MiB=536870912, 1GiB=1073741824, 2GiB=2147483648, 5GiB=5368709120.
_lsblk_stub='lsblk(){ printf "%s\n" \
  "nvme0n1 500107862016 disk" \
  "nvme0n1p1 536870912 part" \
  "nvme0n1p2 1073741824 part" \
  "nvme0n1p3 2147483648 part" \
  "nvme0n1p4 5368709120 part"; }'

@test "partitions_by_size wrong arg count prints usage" {
    run zsh -c 'source "$1"; partitions_by_size 1G' _ "$PLUGIN_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: partitions_by_size"* ]]
}

@test "partitions_by_size rejects an invalid size" {
    run zsh -c 'source "$1"; partitions_by_size zzz 2G' _ "$PLUGIN_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid size"* ]]
}

@test "partitions_by_size rejects min greater than max" {
    run zsh -c 'source "$1"; partitions_by_size 3G 1G' _ "$PLUGIN_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"min-size must be <= max-size"* ]]
}

@test "partitions_by_size filters to the inclusive range and excludes disks" {
    run zsh -c "$_lsblk_stub"'; source "$1"; partitions_by_size 1G 2G' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"nvme0n1p2	1073741824"* ]]   # 1GiB, lower border inclusive
    [[ "$output" == *"nvme0n1p3	2147483648"* ]]   # 2GiB, upper border inclusive
    [[ "$output" != *"nvme0n1p1"* ]]               # 512MiB below range
    [[ "$output" != *"nvme0n1p4"* ]]               # 5GiB above range
    [[ "$output" != *"nvme0n1 "* ]]                # disk excluded
}
