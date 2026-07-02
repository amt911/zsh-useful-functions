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

# mount stub echoing its args; a second stub variant fails.
_mount_ok='mount(){ print "MNT:$*"; return 0; }'
_mount_fail='mount(){ print "MNT:$*"; return 1; }'

# lsblk FSTYPE stub: report a non-NTFS filesystem for any device.
_lsblk_ext4='lsblk(){ print "ext4"; }'
# lsblk FSTYPE stub: report NTFS for any device.
_lsblk_ntfs='lsblk(){ print "ntfs"; }'

@test "mount_partitions no args prints usage" {
    run zsh -c 'source "$1"; mount_partitions' _ "$PLUGIN_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: mount_partitions"* ]]
}

@test "mount_partitions -h prints usage and returns 0" {
    run zsh -c 'source "$1"; mount_partitions -h' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: mount_partitions"* ]]
}

@test "mount_partitions defaults base to /mnt and derives folder from basename" {
    run zsh -c "$_mount_ok"' ; '"$_lsblk_ext4"'; source "$1"; mount_partitions /dev/mapper/veracrypt1' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"MNT:--mkdir /dev/mapper/veracrypt1 /mnt/veracrypt1"* ]]
}

@test "mount_partitions honors -b base and mounts multiple devices" {
    run zsh -c "$_mount_ok"' ; '"$_lsblk_ext4"'; source "$1"; mount_partitions -b /media /dev/sda1 /dev/sdb2' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"MNT:--mkdir /dev/sda1 /media/sda1"* ]]
    [[ "$output" == *"MNT:--mkdir /dev/sdb2 /media/sdb2"* ]]
}

@test "mount_partitions reports a mount failure and returns non-zero" {
    run zsh -c "$_mount_fail"' ; '"$_lsblk_ext4"'; source "$1"; mount_partitions /dev/sda1' _ "$PLUGIN_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"failed to mount /dev/sda1 at /mnt/sda1"* ]]
}

@test "mount_partitions rejects an unknown flag" {
    run zsh -c 'source "$1"; mount_partitions -x /dev/sda1' _ "$PLUGIN_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid option"* ]]
}

@test "mount_partitions -r mounts a device read-only" {
    run zsh -c "$_mount_ok"' ; '"$_lsblk_ext4"'; source "$1"; mount_partitions -r /dev/sda1' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"MNT:-o ro --mkdir /dev/sda1 /mnt/sda1"* ]]
}

@test "mount_partitions mixes read-only and writable devices in one call" {
    run zsh -c "$_mount_ok"' ; '"$_lsblk_ext4"'; source "$1"; mount_partitions -r /dev/nvme1n1p4 /dev/mapper/veracrypt1' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"MNT:-o ro --mkdir /dev/nvme1n1p4 /mnt/nvme1n1p4"* ]]
    [[ "$output" == *"MNT:--mkdir /dev/mapper/veracrypt1 /mnt/veracrypt1"* ]]
}

@test "mount_partitions with only -r (no positional) still mounts, no usage" {
    run zsh -c "$_mount_ok"' ; '"$_lsblk_ext4"'; source "$1"; mount_partitions -r /dev/sda1' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Usage: mount_partitions"* ]]
}

@test "mount_partitions mounts read-only devices before writable ones" {
    run zsh -c "$_mount_ok"' ; '"$_lsblk_ext4"'; source "$1"; mount_partitions -r /dev/nvme1n1p4 /dev/mapper/veracrypt1' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    ro_line=$(printf '%s\n' "$output" | grep -n 'MNT:-o ro --mkdir /dev/nvme1n1p4' | cut -d: -f1)
    w_line=$(printf '%s\n' "$output" | grep -n 'MNT:--mkdir /dev/mapper/veracrypt1' | cut -d: -f1)
    [ -n "$ro_line" ] && [ -n "$w_line" ]
    [ "$ro_line" -lt "$w_line" ]
}

@test "mount_partitions long-form --read-only mounts read-only" {
    run zsh -c "$_mount_ok"' ; '"$_lsblk_ext4"'; source "$1"; mount_partitions --read-only /dev/sda1' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"MNT:-o ro --mkdir /dev/sda1 /mnt/sda1"* ]]
}

# ntfs-3g stub echoing its args.
_ntfs_ok='ntfs-3g(){ print "NTFS3G:$*"; return 0; }'
# mkdir stub: the ntfs-3g branch calls a real `mkdir -p` (ntfs-3g has no
# --mkdir); stub it so the test doesn't depend on write access to the real
# default base (/mnt, typically root-owned) — mirrors why `mount` is stubbed.
_mkdir_ok='mkdir(){ return 0; }'

@test "mount_partitions uses ntfs-3g for an NTFS device" {
    run zsh -c "$_mount_ok"' ; '"$_ntfs_ok"' ; '"$_mkdir_ok"' ; '"$_lsblk_ntfs"'; source "$1"; mount_partitions /dev/sda1' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"NTFS3G:/dev/sda1 /mnt/sda1"* ]]
    [[ "$output" != *"MNT:"* ]]
}

@test "mount_partitions mounts an NTFS device read-only with -o ro" {
    run zsh -c "$_mount_ok"' ; '"$_ntfs_ok"' ; '"$_mkdir_ok"' ; '"$_lsblk_ntfs"'; source "$1"; mount_partitions -r /dev/sda1' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"NTFS3G:-o ro /dev/sda1 /mnt/sda1"* ]]
}

# rsync stub echoing its args; a failing variant for the abort test.
_rsync_ok='rsync(){ print "RS:$*"; return 0; }'
_rsync_fail='rsync(){ print "RS:$*"; return 1; }'

@test "rsync_fanout no args prints usage" {
    run zsh -c 'source "$1"; rsync_fanout' _ "$PLUGIN_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: rsync_fanout"* ]]
}

@test "rsync_fanout source but no dest prints usage" {
    run zsh -c 'source "$1"; rsync_fanout /mnt/src/' _ "$PLUGIN_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: rsync_fanout"* ]]
}

@test "rsync_fanout -h prints usage and returns 0" {
    run zsh -c 'source "$1"; rsync_fanout -h' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: rsync_fanout"* ]]
}

@test "rsync_fanout default uses -avc and built-in excludes, no delete/dry-run" {
    run zsh -c "$_rsync_ok"'; source "$1"; rsync_fanout /mnt/src/ /mnt/dst1' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RS:-avc "* ]]
    [[ "$output" == *"--exclude System Volume Information"* ]]
    [[ "$output" == *'--exclude $RECYCLE.BIN'* ]]
    [[ "$output" == *"--exclude Versiones anteriores"* ]]
    [[ "$output" == *"--exclude .Trash-1000"* ]]
    [[ "$output" == *"/mnt/src/ /mnt/dst1"* ]]
    [[ "$output" != *"--delete"* ]]
    [[ "$output" != *"--dry-run"* ]]
}

@test "rsync_fanout -D adds --delete and -n adds --dry-run" {
    run zsh -c "$_rsync_ok"'; source "$1"; rsync_fanout -D -n /mnt/src/ /mnt/dst1' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"--delete"* ]]
    [[ "$output" == *"--dry-run"* ]]
}

@test "rsync_fanout appends extra -x excludes after the built-ins" {
    run zsh -c "$_rsync_ok"'; source "$1"; rsync_fanout -x foo -x bar /mnt/src/ /mnt/dst1' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"--exclude foo"* ]]
    [[ "$output" == *"--exclude bar"* ]]
}

@test "rsync_fanout runs once per destination" {
    run zsh -c "$_rsync_ok"'; source "$1"; rsync_fanout /mnt/src/ /mnt/dst1 /mnt/dst2' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"/mnt/src/ /mnt/dst1"* ]]
    [[ "$output" == *"/mnt/src/ /mnt/dst2"* ]]
}

@test "rsync_fanout aborts on first rsync failure" {
    run zsh -c "$_rsync_fail"'; source "$1"; rsync_fanout /mnt/src/ /mnt/dst1 /mnt/dst2' _ "$PLUGIN_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"rsync to /mnt/dst1 failed"* ]]
    [[ "$output" != *"/mnt/src/ /mnt/dst2"* ]]
}
