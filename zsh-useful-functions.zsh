#!/bin/zsh

if [ "$USEFUL_FUNCTIONS" != yes ]; then
    USEFUL_FUNCTIONS=yes
else
    return 0
fi 

# Personal scripts rewritten to functions, so they can be called directly
# REWRITE THIS FUNCTION SO IT CAN TAKE AN ARBITRARY AMOUNT OF SWITCHES
convert_png_to_jpg() {
    if [ "$#" -eq 0 ]; then
        echo "Usage: convert_png_to_jpg [-r] <quality-number> <path>"
        echo "Example: convert_png_to_jpg ."
        echo "Example: convert_png_to_jpg -r ."
        echo "Example: convert_png_to_jpg -r 33 ."
        return 1
    fi

    local f
    if [ "$#" -eq 1 ]; then
        for f in "$1"/*.png; do
	        jpg_name=${f/%.png/.jpg}
	        convert "$f" "$jpg_name"
        done

    elif [ "$#" -eq 2 ]; then
        for f in "$2"/**/*.png; do
	        jpg_name=${f/%.png/.jpg}
	        convert "$f" "$jpg_name"
        done
    else
        for f in "$3"/**/*.png; do
	        jpg_name=${f/%.png/.jpg}
	        convert "$f" -quality "$2" "$jpg_name"
        done
    fi
    unset f
}

batch_resize(){
    if [ "$#" -eq 2 ]; then
        [ ! -d "resized" ] && mkdir resized
        
        for f in "$1"/*.png; do
            convert "$f" -resize "$2" -filter Point "resized/$f"
        done
    elif [ "$#" -eq 3 ]; then
        for f in "$2"/*.png; do
            convert "$f" -resize "$3" -filter Point "$f"
        done
    else
        echo "Usage: batch_resize [-f] <directory> <percentage>"
        echo "Example: batch_resize . 20%"
        echo "Example: batch_resize -f . 33%"
        return 1
    fi
}

batch_crop() {
    if [ "$#" -eq 2 ]; then
        [ ! -d "cropped" ] && mkdir cropped
        
        for f in "$1"/*.png; do
            convert "$f" -crop "$2" "cropped/$f"
        done
    elif [ "$#" -eq 3 ]; then
        for f in "$2"/*.png; do
            convert "$f" -crop "$3" "$f"
        done
    else
        echo "Usage: batch_crop [-f] <directory> {x}x{y}{+/-}{x}{+/-}{y}"
        echo "Example: batch_crop . 12x13+1+2"
        echo "Example: batch_crop -f . 33x33"
        return 1
    fi
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
}

# Converts back root snapshots to read-write.
# Useful after a dedupe has been done.
btrfs_snapper_root_ro(){
	for i in /.snapshots/**/snapshot_AUX
	do
		btrfs subvolume snapshot -r "$i" "${i::-4}"
		btrfs subvolume delete "$i"
	done
}


# Generates a random string comprised of numbers and letters
# $1: String length. Defaults to 16
rand(){
    local -r LEN="${1:-16}"

    # Only gets numbers and letters
    tr -dc "a-zA-Z0-9" < /dev/random | head -c "$LEN"
}


# Generates a random string comprised of letters
# $1: String length. Defaults to 16
rand_letters(){
    local -r LEN="${1:-16}"

    # Only gets the letters
    tr -dc "a-zA-Z" < /dev/random | head -c "$LEN"
}


# Generates a random number
# $1: String length. Defaults to 16
rand_num(){
    local -r LEN="${1:-16}"

    # Only gets the numbers
    tr -dc "0-9" < /dev/random | head -c "$LEN"
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

        for (( i=0; i<$NUM_FILES; i++ ))
        do
            dd if=/dev/urandom of="$DIR/$(rand)" bs=$(( $MIN + $(rand_num) % MAX ))M count=1
        done
        unset i
    else
        echo "Not enough arguments"
        return 1
    fi    
}

# $1: First hash file
# $2: Second hash file
check_hashes(){
    # Strip filename from first hash file
    awk '{print $1}' $1 > aux

    while IFS= read -r line; do
        if grep -i "$line" "$2";
        then
            echo -e "$line: ${GREEN}OK${NO_COLOR}"
        else
            echo -e "$line: ${RED}NOT FOUND${NO_COLOR}"
        fi
    done < "aux"
    rm aux
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

    local old_ifs=IFS
    local segments_a segments_b remainder_a remainder_b
    local error_segment err_code
    local diff_res

    while IFS= read -r -d '' file
    do
        other_dir=$(echo "$file" | sed "s/\/$2\//\/$3\//")
        echo -e "--------------------------------------------- File $file ---------------------------------------------\n"
        if [ -f "$other_dir" ];
        then
            segments_a=$(($(du -sb "$file" | cut -f1) / THRESHOLD))
            remainder_a=$(($(du -sb "$file" | cut -f1) % THRESHOLD))

            segments_b=$(($(du -sb "$other_dir" | cut -f1) / THRESHOLD))
            remainder_b=$(($(du -sb "$other_dir" | cut -f1) % THRESHOLD))

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

    local old_ifs=IFS
    local size_a size_b
    local err_code
    local diff_res

    while IFS= read -r -d '' file
    do
        other_dir=$(echo "$file" | sed "s/\/$2\//\/$3\//")
        echo -e "--------------------------------------------- File $file ---------------------------------------------\n"
        if [ -f "$other_dir" ];
        then
            size_a=$(du -sb "$file" | cut -f1)
            size_b=$(du -sb "$other_dir" | cut -f1)

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
    # shopt -s nullglob
    for g in $(find /sys/kernel/iommu_groups/* -maxdepth 0 -type d | sort -V); do
        echo "IOMMU Group ${g##*/}:"
        for d in $g/devices/*; do
            echo -e "\t$(lspci -nns ${d##*/})"
        done;
    done;
}


mount_veracrypt(){

    if [ "$#" -eq "0" ] || ! echo "$1" | grep -E "^[01]{1}";
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
        for (( i=0; i<${#PARTITIONS[@]}; i++ ))
        do
            echo "$password" | cryptsetup --type tcrypt --veracrypt-pim "$pim" open "${PARTITIONS[i]}" "veracrypt$(( i + 1 ))" -
            mount --mkdir "/dev/mapper/veracrypt$(( i + 1 ))" "/mnt/veracrypt$(( i + 1 ))"
        done
    else
        for (( i=0; i<${#PARTITIONS[@]}; i++ ))
        do
            echo "$password" | cryptsetup --type tcrypt --veracrypt-pim "$pim" open "${PARTITIONS[i]}" "veracrypt$(( 64 - i ))" -
            mount --mkdir "/dev/mapper/veracrypt$(( 64 - i ))" "/mnt/veracrypt$(( 64 - i ))"
        done
    fi

    # Unsets both password and PIM to avoid a leak
    unset password
    unset pim
}


mount_partitions(){
    if [ "$#" -eq "0" ];
    then
        echo "Usage: $0 <devices-to-be-decrypted>"
        exit 1
    fi

    local -r PARTITIONS=( "$@" )

    echo -n "Password: "
    read -rs password

    for i in "${PARTITIONS[@]}"
    do
        local dm_name=$(echo "$i" | cut -d/ -f3)

        echo "$password" | cryptsetup open $i $dm_name -
    done

    unset password
}