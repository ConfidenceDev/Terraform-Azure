cat << E0F >> ~/.ssh/config

Host ${hostname}
    Hostname ${hostname}
    User ${user}
    IdentityFile ${identityfile}

EOF