#!/bin/zsh

if [ "$USEFUL_FUNCTIONS" != yes ]; then
    USEFUL_FUNCTIONS=yes
else
    return 0
fi 

# Personal scripts rewritten to functions, so they can be called directly
# Convert PNG files to JPG.
convert_png_to_jpg() {
    local -a o_recursive o_help
    zparseopts -D -E -F -- r=o_recursive h=o_help -help=o_help 2>/dev/null
    local -r parse_rc=$?

    if [ "$parse_rc" -ne "0" ];
    then
        echo "Error: invalid option" >&2
        return 1
    fi

    if [ -n "$o_help" ] || [ "$#" -eq "0" ];
    then
        echo "Usage: convert_png_to_jpg [-r] [<quality>] <path>"
        echo "  -r          recurse into subdirectories"
        echo "  <quality>   optional JPEG quality (1-100)"
        echo "Example: convert_png_to_jpg ."
        echo "Example: convert_png_to_jpg -r 33 ."
        [ -n "$o_help" ] && return 0
        return 1
    fi

    local im=convert
    (( $+commands[magick] )) && im=magick

    local quality path
    if [ "$#" -eq "1" ];
    then
        path="$1"
    elif [ "$#" -eq "2" ];
    then
        quality="$1"; path="$2"
    else
        echo "Error: expected [<quality>] <path>" >&2
        return 1
    fi

    local -a pngs
    if [ -n "$o_recursive" ];
    then
        pngs=("$path"/**/*.png(N))
    else
        pngs=("$path"/*.png(N))
    fi

    local f jpg_name
    for f in "${pngs[@]}"; do
        jpg_name="${f/%.png/.jpg}"
        if [ -n "$quality" ];
        then
            "$im" "$f" -quality "$quality" "$jpg_name"
        else
            "$im" "$f" "$jpg_name"
        fi
    done
    unset f jpg_name
}

batch_resize(){
    local -a o_inplace o_help
    zparseopts -D -E -F -- f=o_inplace h=o_help -help=o_help 2>/dev/null
    local -r parse_rc=$?

    if [ "$parse_rc" -ne "0" ];
    then
        echo "Error: invalid option" >&2
        return 1
    fi

    if [ -n "$o_help" ] || [ "$#" -ne "2" ];
    then
        echo "Usage: batch_resize [-f] <directory> <percentage>"
        echo "  -f    resize in place (overwrite originals); else write to resized/"
        echo "Example: batch_resize . 20%"
        echo "Example: batch_resize -f . 33%"
        [ -n "$o_help" ] && return 0
        return 1
    fi

    local im=convert
    (( $+commands[magick] )) && im=magick

    local -r dir="$1" pct="$2"
    [ -z "$o_inplace" ] && mkdir -p resized

    local f
    for f in "$dir"/*.png(N); do
        if [ -n "$o_inplace" ];
        then
            "$im" "$f" -resize "$pct" -filter Point "$f"
        else
            "$im" "$f" -resize "$pct" -filter Point "resized/${f:t}"
        fi
    done
    unset f
}

batch_crop() {
    local -a o_inplace o_help
    zparseopts -D -E -F -- f=o_inplace h=o_help -help=o_help 2>/dev/null
    local -r parse_rc=$?

    if [ "$parse_rc" -ne "0" ];
    then
        echo "Error: invalid option" >&2
        return 1
    fi

    if [ -n "$o_help" ] || [ "$#" -ne "2" ];
    then
        echo "Usage: batch_crop [-f] <directory> {x}x{y}{+/-}{x}{+/-}{y}"
        echo "  -f    crop in place (overwrite originals); else write to cropped/"
        echo "Example: batch_crop . 12x13+1+2"
        echo "Example: batch_crop -f . 33x33"
        [ -n "$o_help" ] && return 0
        return 1
    fi

    local im=convert
    (( $+commands[magick] )) && im=magick

    local -r dir="$1" geom="$2"
    [ -z "$o_inplace" ] && mkdir -p cropped

    local f
    for f in "$dir"/*.png(N); do
        if [ -n "$o_inplace" ];
        then
            "$im" "$f" -crop "$geom" "$f"
        else
            "$im" "$f" -crop "$geom" "cropped/${f:t}"
        fi
    done
    unset f
}

shrink_png_lossy() {
	if [ "$#" -ne 2 ]; then
		echo "Usage: shrink_png_lossy {min-max} {image(s)}"
		return 1
	else
		pngquant --skip-if-larger --force --ext "-new.png" --quality "$1" --speed 1 --strip "$2"
	fi
}

# jdupes -rB /
# duperemove -rdA /

# Converts root read-only subvolumes created by snapper to read-write.
# Useful when trying to dedupe with dupremove or jdupes.
btrfs_snapper_root_rw(){
	for i in /.snapshots/**/snapshot
	do
		btrfs subvolume snapshot "$i" "${i}_AUX"
		btrfs subvolume delete "$i"
	done

    unset i
}

# Converts back root snapshots to read-write.
# Useful after a dedupe has been done.
btrfs_snapper_root_ro(){
	for i in /.snapshots/**/snapshot_AUX
	do
		btrfs subvolume snapshot -r "$i" "${i::-4}"
		btrfs subvolume delete "$i"
	done

    unset i
}


# Generates a random string comprised of numbers and letters
# $1: String length. Defaults to 16
rand(){
    local -r LEN="${1:-16}"

    # Only gets numbers and letters
    tr -dc "a-zA-Z0-9" < /dev/urandom | head -c "$LEN"
}


# Generates a random string comprised of letters
# $1: String length. Defaults to 16
rand_letters(){
    local -r LEN="${1:-16}"

    # Only gets the letters
    tr -dc "a-zA-Z" < /dev/urandom | head -c "$LEN"
}


# Generates a random number
# $1: String length. Defaults to 16
rand_num(){
    local -r LEN="${1:-16}"

    # Only gets the numbers
    tr -dc "0-9" < /dev/urandom | head -c "$LEN"
}

create_random_files(){
    if [ "$#" -eq "0" ];
    then
        echo "Usage: create_random_files <number-of-files> <min-size> <max-size> <directory>"
        return 1
    fi

    if [ "$#" -eq "4" ]
    then
        local -r NUM_FILES=$1
        local -r MIN=$2
        local -r MAX=$3
        
        if [ "${4: -1}" = "/" ];
        then
            local -r DIR=${4::-1}
        else
            local -r DIR=$4
        fi

        local -r RANGE=$(( MAX - MIN + 1 ))
        if [ "$RANGE" -le 0 ];
        then
            echo "Error: max-size must be >= min-size" >&2
            return 1
        fi

        local i size
        for (( i=0; i<NUM_FILES; i++ ))
        do
            size=$(( MIN + RANDOM % RANGE ))
            (( size < 1 )) && size=1
            dd if=/dev/urandom of="$DIR/$(rand)" bs="${size}M" count=1
        done
        unset i size
    else
        echo "Not enough arguments"
        return 1
    fi    
}

# $1: First hash file
# $2: Second hash file
check_hashes(){
    if [ "$#" -ne 2 ];
    then
        echo "Usage: check_hashes <first-hash-file> <second-hash-file>"
        return 1
    fi

    local -r GREEN=$'\e[32m' RED=$'\e[31m' NO_COLOR=$'\e[0m'
    local -r tmp="$(mktemp)"

    # Strip filename from first hash file
    awk '{print $1}' "$1" > "$tmp"

    local line
    while IFS= read -r line; do
        if grep -qi -- "$line" "$2";
        then
            echo -e "$line: ${GREEN}OK${NO_COLOR}"
        else
            echo -e "$line: ${RED}NOT FOUND${NO_COLOR}"
        fi
    done < "$tmp"

    rm -f "$tmp"
    unset line
}

# Checks if two files are the same by comparing every byte of both files. 
# It is a different approach than using hashes. I recommend using hashes 
# first and then trying this function to double check.
check_binary_contents(){
    if [ "$#" -lt "3" ];
    then
        echo "You have to provide the following arguments:
1: Path to folder where the two folders reside
2: Original folder inside \$1
3: Second folder inside \$1"
        return 1
    fi

    if [ ! -d "$1/$2" ] || [ ! -d "$1/$3" ];
    then
        echo "One of the subfolders (or both) does not exist"
        return 33
    fi

    local -r THRESHOLD="1073741824"      # Actual THRESHOLD in bytes. MUST BE POWER OF 2 AND AT LEAST 2^4 (16)
    # local -r THRESHOLD="512"      # Actual THRESHOLD in bytes. MUST BE POWER OF 2 AND AT LEAST 2^4 (16)    

    local old_ifs=$IFS
    local segments_a segments_b remainder_a remainder_b
    local error_segment err_code
    local diff_res

    while IFS= read -r -d '' file
    do
        local other_dir="$1/$3/${file#$1/$2/}"
        echo -e "--------------------------------------------- File $file ---------------------------------------------\n"
        if [ -f "$other_dir" ];
        then
            segments_a=$(($(stat -c%s "$file") / THRESHOLD))
            remainder_a=$(($(stat -c%s "$file") % THRESHOLD))

            segments_b=$(($(stat -c%s "$other_dir") / THRESHOLD))
            remainder_b=$(($(stat -c%s "$other_dir") % THRESHOLD))

            error_segment="0"

             # Enter if both files have the same number of segments and remainder.
            if [ "$segments_a" -eq "$segments_b" ] && [ "$remainder_a" -eq "$remainder_b" ];
            then
                # Iteration for every segment of both files
                for (( i=0; i<segments_a; i++ ))
                do
                    diff_res=$(diff <(od -tx1 --skip-bytes="$(( i * THRESHOLD ))" --read-bytes="$THRESHOLD" "$file") <(od -tx1 --skip-bytes="$(( i * THRESHOLD ))" --read-bytes="$THRESHOLD" "$other_dir"))
                    
                    err_code="$?"
                    
                    # Comparing both file segments
                    if [ "$err_code" -ne "0" ];
                    then
                        echo -e "\n[ERROR] $file and $other_dir are different!!!\n"
                        echo -e "$diff_res\n"
                        error_segment="1"
                    fi
                done

                # If the file size was not aligned with a power of 2, we check the last remaining segment.
                if [ "$remainder_a" -gt "0" ];
                then
                    diff_res=$(diff <(od -tx1 --skip-bytes="$(( segments_a * THRESHOLD ))" --read-bytes="$remainder_a" "$file") <(od -tx1 --skip-bytes="$(( segments_b * THRESHOLD ))" --read-bytes="$remainder_b" "$other_dir"))
                    
                    err_code="$?"

                    if [ "$err_code" -ne "0" ];
                    then
                        echo -e "[ERROR] $file and $other_dir are different!!!\n"
                        echo -e "$diff_res\n"
                        error_segment="1"
                    fi                    
                fi

                # To avoid printing lots of messages when a segment is the same, we just echo it outside the loop once.
                if [ "$error_segment" -eq "0" ];
                then
                    echo -e "[GOOD] Both files are the same\n"
                fi                
            else
                echo -e "[ERROR] $file and $other_dir are different and have different size!!!\n"
            fi
        else
            echo -e "[WARNING] File $file does not exist on $3\n"
        fi

        echo -e "---------------------------------------------------------------------------------------------------------------------------------------------\n"
    done <  <(find "$1/$2" -type f -print0)

    IFS=$old_ifs
    unset i

    unset file
}

# Checks if two files are the same by comparing every byte of both files. 
# It is a different approach than using hashes. I recommend using hashes 
# first and then trying this function to double check.
check_binary_contents_cmp(){
    if [ "$#" -lt "3" ];
    then
        echo "You have to provide the following arguments:
1: Path to folder where the two folders reside
2: Original folder inside \$1
3: Second folder inside \$1"
        return 1
    fi

    if [ ! -d "$1/$2" ] || [ ! -d "$1/$3" ];
    then
        echo "One of the subfolders (or both) does not exist"
        return 33
    fi

    local -r THRESHOLD="1073741824"      # Actual THRESHOLD in bytes. MUST BE POWER OF 2 AND AT LEAST 2^4 (16)
    # local -r THRESHOLD="512"      # Actual THRESHOLD in bytes. MUST BE POWER OF 2 AND AT LEAST 2^4 (16)    

    local old_ifs=$IFS
    local size_a size_b
    local err_code
    local diff_res

    while IFS= read -r -d '' file
    do
        local other_dir="$1/$3/${file#$1/$2/}"
        echo -e "--------------------------------------------- File $file ---------------------------------------------\n"
        if [ -f "$other_dir" ];
        then
            size_a=$(stat -c%s "$file")
            size_b=$(stat -c%s "$other_dir")

            if [ "$size_a" -eq "$size_b" ];
            then
                cmp "$file" "$other_dir"
                err_code="$?"


                if [ "$err_code" -ne "0" ];
                then
                    echo -e "[ERROR] $file and $other_dir are different!!!\n"                  
                else
                    echo -e "[GOOD] Both files are the same\n"
                fi
            else
                echo -e "[ERROR] $file and $other_dir are different and have different size!!!\n"
            fi
        else
            echo -e "[WARNING] File $file does not exist on $3\n"
        fi                
        echo -e "---------------------------------------------------------------------------------------------------------------------------------------------\n"
    done <  <(find "$1/$2" -type f -print0)

    IFS=$old_ifs

    unset file
}

iommu_groups(){
    local g d
    # (/nN): directories only, numeric sort, nullglob — robust, no word-splitting.
    for g in /sys/kernel/iommu_groups/*(/nN); do
        echo "IOMMU Group ${g:t}:"
        for d in "$g"/devices/*(N); do
            echo -e "\t$(lspci -nns "${d:t}")"
        done
    done

    unset g d
}

# List partitions whose size is within [min, max] (inclusive).
# Sizes accept IEC suffixes (K/M/G/T, base 1024) or raw bytes.
partitions_by_size(){
    if [ "$#" -ne 2 ];
    then
        echo "Usage: partitions_by_size <min-size> <max-size>"
        echo "  Sizes accept IEC suffixes: K M G T (e.g. 500M, 1G, 2T), or raw bytes."
        echo "  Prints NAME<TAB>SIZE for partitions with min <= size <= max."
        echo "Example: partitions_by_size 1G 2G"
        return 1
    fi

    local min max
    min=$(numfmt --from=iec "$1" 2>/dev/null)
    max=$(numfmt --from=iec "$2" 2>/dev/null)

    if [ -z "$min" ] || [ -z "$max" ];
    then
        echo "Error: invalid size (use IEC suffixes like 500M, 1G, 2T, or bytes)" >&2
        return 1
    fi

    if [ "$min" -gt "$max" ];
    then
        echo "Error: min-size must be <= max-size" >&2
        return 1
    fi

    local name size type
    while read -r name size type;
    do
        if [ "$type" = "part" ] && [ "$size" -ge "$min" ] && [ "$size" -le "$max" ];
        then
            printf '%s\t%s\n' "$name" "$size"
        fi
    done < <(lsblk -b -l -n -o NAME,SIZE,TYPE)
    unset name size type
}

# Mount one or more devices under a base directory (default /mnt), creating a
# subdirectory named after each device's basename.
mount_partitions(){
    local -a o_base o_ro o_help
    zparseopts -D -E -F -- b:=o_base -base:=o_base r+:=o_ro -read-only+:=o_ro h=o_help -help=o_help 2>/dev/null
    local -r parse_rc=$?

    if [ "$parse_rc" -ne "0" ];
    then
        echo "Error: invalid option" >&2
        return 1
    fi

    if [ -n "$o_help" ] || { [ "$#" -eq "0" ] && [ "${#o_ro}" -eq "0" ]; };
    then
        echo "Usage: mount_partitions [-b <base-dir>] [-r <ro-device>]... <device>..."
        echo "  Mounts each <device> at <base-dir>/<device-basename>, creating the dir."
        echo "  -b, --base       base mount directory (default: /mnt)"
        echo "  -r, --read-only  mount this device read-only (repeatable)"
        echo "  -h, --help       show this help"
        echo "Example: mount_partitions -r /dev/nvme1n1p4 /dev/mapper/veracrypt1"
        echo "Example: mount_partitions -b /media /dev/sda1"
        [ -n "$o_help" ] && return 0
        return 1
    fi

    local -r base="${o_base[2]:-/mnt}"

    # zparseopts accumulates each -r occurrence; keep only the device values,
    # dropping any captured flag tokens (robust to both storage forms).
    local -a ro_devs
    local tok
    for tok in "${o_ro[@]}"
    do
        [ "$tok" = "-r" ] || [ "$tok" = "--read-only" ] && continue
        ro_devs+=("$tok")
    done
    unset tok

    local i target
    for i in "${ro_devs[@]}"
    do
        target="$base/${i:t}"
        if ! mount -o ro --mkdir "$i" "$target";
        then
            echo "Error: failed to mount $i at $target" >&2
            unset i target
            return 1
        fi
    done
    for i in "$@"
    do
        target="$base/${i:t}"
        if ! mount --mkdir "$i" "$target";
        then
            echo "Error: failed to mount $i at $target" >&2
            unset i target
            return 1
        fi
    done
    unset i target
}


open_mount_veracrypt(){

    if [ "$#" -eq "0" ] || ! echo "$1" | grep -E "^[01]{1}" > /dev/null;
    then
        echo "Usage: mount_veracrypt <0: ascending mount directory / 1: descending mount directory> <partitions>"
        return 1
    fi


    local -r ASC_DESC="$1"

    # Shifts by 1 the argument list to get all the partition names.
    shift

    local -r PARTITIONS=( "$@" )


    echo -n "Password: "
    read -rs password

    echo -ne "\nPIM: "
    read -rs pim

    if [ "$ASC_DESC" -eq "0" ];
    then
        for (( i=1; i<=${#PARTITIONS[@]}; i++ ))
        do
            print -rn -- "$password" | cryptsetup --type tcrypt --veracrypt-pim "$pim" open "${PARTITIONS[i]}" "veracrypt$(( i ))" -

            [ "$?" -ne "0" ] && return 1

            mount --mkdir "/dev/mapper/veracrypt$(( i ))" "/mnt/veracrypt$(( i ))"

            [ "$?" -ne "0" ] && return 1
        done
    else
        for (( i=1; i<=${#PARTITIONS[@]}; i++ ))
        do
            print -rn -- "$password" | cryptsetup --type tcrypt --veracrypt-pim "$pim" open "${PARTITIONS[i]}" "veracrypt$(( 64 - i + 1 ))" -

            [ "$?" -ne "0" ] && return 1

            mount --mkdir "/dev/mapper/veracrypt$(( 64 - i + 1 ))" "/mnt/veracrypt$(( 64 - i + 1 ))"

            [ "$?" -ne "0" ] && return 1
        done
    fi

    unset i

    # Unsets both password and PIM to avoid a leak
    unset password
    unset pim
}


# Unlock a single device according to the mode flags of the calling
# open-partitions invocation. zsh locals are dynamically scoped, so this sees
# the caller's o_fido/o_keyfile/o_vera/keyfile_loc/password/pim. Returns the
# unlock command's exit code.
_open_partitions_unlock() {
    local dev="$1" dm="${1:t}"

    if [ -n "$o_fido" ];
    then
        systemd-cryptsetup attach "$dm" "$dev" - fido2-device=auto
    elif [ -n "$o_keyfile" ];
    then
        cryptsetup --key-file "$keyfile_loc" open "$dev" "$dm"
    elif [ -n "$o_vera" ];
    then
        print -rn -- "$password" | cryptsetup --type tcrypt --veracrypt-pim "$pim" open "$dev" "$dm" -
    else
        print -rn -- "$password" | cryptsetup open "$dev" "$dm" -
    fi
}


# Opens (unlocks) one or more LUKS/dm-crypt devices.
# Modes: password (default), keyfile (-k <file>), FIDO2 (-f / --fido2), veracrypt/tcrypt (-v / --veracrypt).
# The mapper name is the last path component of each device (${dev:t}),
# so /dev/disk/by-uuid/<uuid> maps to /dev/mapper/<uuid>.
open-partitions(){
    local -a o_keyfile o_fido o_vera o_parallel o_help
    # -E keeps parsing tolerant of flags that appear after a device (so a stray
    # "-k"/"-f" is never silently swallowed as a device path); -F rejects
    # unknown flags. Together they keep the -k/-f conflict check reachable
    # regardless of argument order.
    zparseopts -D -E -F -- k:=o_keyfile f=o_fido -fido2=o_fido v=o_vera -veracrypt=o_vera p=o_parallel -parallel=o_parallel h=o_help -help=o_help 2>/dev/null
    local -r parse_rc=$?

    if [ "$parse_rc" -ne "0" ];
    then
        echo "Error: invalid option" >&2
        return 1
    fi

    if [ -n "$o_help" ] || [ "$#" -eq "0" ];
    then
        echo "Usage: open-partitions [-k <keyfile> | -f | --fido2 | -v | --veracrypt] [-p] <device>..."
        echo "  (no flag)      password mode  — prompt once, unlock every device"
        echo "  -k <keyfile>   keyfile mode   — cryptsetup --key-file <keyfile>"
        echo "  -f, --fido2    FIDO2 mode     — systemd-cryptsetup attach ... fido2-device=auto"
        echo "  -v, --veracrypt veracrypt/tcrypt — prompt password+PIM once, cryptsetup --type tcrypt"
        echo "  -p, --parallel unlock devices concurrently (ignored for FIDO2)"
        echo "  -h, --help     show this help"
        [ -n "$o_help" ] && return 0
        return 1
    fi

    local -i mode_count=0
    [ -n "$o_keyfile" ] && (( mode_count++ ))
    [ -n "$o_fido" ] && (( mode_count++ ))
    [ -n "$o_vera" ] && (( mode_count++ ))
    if [ "$mode_count" -gt "1" ];
    then
        echo "Error: -k, -f/--fido2 and -v/--veracrypt are mutually exclusive" >&2
        return 1
    fi

    local -r keyfile_loc="${o_keyfile[2]}"

    local password="" pim=""
    if [ -z "$o_keyfile" ] && [ -z "$o_fido" ];
    then
        echo -n "Password: "
        read -rs password
        echo
        if [ -n "$o_vera" ];
        then
            echo -n "PIM: "
            read -rs pim
            echo
        fi
    fi

    if [ -n "$o_parallel" ] && [ -n "$o_fido" ];
    then
        echo "Warning: FIDO2 uses a hardware token; ignoring --parallel (running sequentially)" >&2
    fi

    local rc=0 i
    if [ -n "$o_parallel" ] && [ -z "$o_fido" ];
    then
        local -a pids
        local -A pid_dev
        local p
        for i in "$@"
        do
            _open_partitions_unlock "$i" &
            pids+=($!)
            pid_dev[$!]="$i"
        done
        for p in "${pids[@]}"
        do
            if ! wait "$p";
            then
                echo "Error: failed to unlock ${pid_dev[$p]}" >&2
                rc=1
            fi
        done
        unset p pids pid_dev
    else
        for i in "$@"
        do
            if ! _open_partitions_unlock "$i";
            then
                rc=1
                break
            fi
        done
    fi
    unset i

    # Unsets secrets to avoid a leak
    unset password pim
    return $rc
}


# Back-compat wrapper for the previous underscore name.
open_partitions(){
    open-partitions "$@"
}



close_partitions(){
    if [ "$#" -eq "0" ];
    then
        echo "Usage: $0 part1 part2 ..."
        return 1
    fi

    local -r PARTITIONS=( "$@" )

    for i in "${PARTITIONS[@]}"
    do
        cryptsetup close "$i"
    done
    unset i
}