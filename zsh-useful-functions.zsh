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

# jdupes -R -B /
# duperemove -r -d -A /

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

        echo $DIR
        # for (( i=0; i<$NUM_FILES; i++ ))
        # do
        #     dd if=/dev/urandom of="$DIR/$(rand)" bs=$(( $MIN + $(rand_num) % MAX ))M count=1
        # done
        # unset i
    else
        echo "Not enough arguments"
        return 1
    fi    
}