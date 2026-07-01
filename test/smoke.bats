load test_helper

@test "plugin file sources cleanly in zsh" {
    run zsh -c 'source "$1"' _ "$PLUGIN_FILE"
    [ "$status" -eq 0 ]
}
