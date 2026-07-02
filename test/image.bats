load test_helper

@test "convert_png_to_jpg no args prints usage" {
    run_plugin convert_png_to_jpg
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: convert_png_to_jpg"* ]]
}

@test "convert_png_to_jpg converts non-recursively, no quality" {
    cd "$BATS_TEST_TMPDIR"
    touch a.png
    mkdir sub; touch sub/b.png
    run_plugin convert_png_to_jpg .
    [ "$status" -eq 0 ]
    [[ "$output" == *"IM:./a.png ./a.jpg"* ]]
    [[ "$output" != *"b.png"* ]]
}

@test "convert_png_to_jpg -r recurses and applies quality" {
    cd "$BATS_TEST_TMPDIR"
    touch a.png
    mkdir sub; touch sub/b.png
    run_plugin convert_png_to_jpg -r 33 .
    [ "$status" -eq 0 ]
    [[ "$output" == *"-quality 33"* ]]
    [[ "$output" == *"sub/b.jpg"* ]]
}

@test "convert_png_to_jpg unknown flag errors" {
    run_plugin convert_png_to_jpg -x .
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid option"* ]]
}

@test "batch_resize writes to resized/<basename> and creates the dir" {
    cd "$BATS_TEST_TMPDIR"
    touch a.png
    run_plugin batch_resize . 50%
    [ "$status" -eq 0 ]
    [[ "$output" == *"-resize 50%"* ]]
    [[ "$output" == *"resized/a.png"* ]]
    [ -d resized ]
}

@test "batch_resize -f resizes in place" {
    cd "$BATS_TEST_TMPDIR"
    touch a.png
    run_plugin batch_resize -f . 33%
    [ "$status" -eq 0 ]
    [[ "$output" == *"IM:./a.png -resize 33% -filter Point ./a.png"* ]]
    [ ! -d resized ]
}

@test "batch_resize wrong arg count prints usage" {
    run_plugin batch_resize .
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: batch_resize"* ]]
}
