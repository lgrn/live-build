if status is-interactive
    # keychain configuration. add new lines for each key (-a = append)
    set --erase SSH_AUTOLOAD
    set -al SSH_AUTOLOAD ~/.ssh/id_ed25519
    # set -Ua SSH_AUTOLOAD ~/.ssh/id_ed25519_second
    # set -Ua SSH_AUTOLOAD ~/.ssh/id_ed25519_third
    # (...)

    # pass all keys above to keychain
    keychain --eval $SSH_AUTOLOAD | source

    # initialize atuin (no remote sync by default)
    atuin init fish | source
end
