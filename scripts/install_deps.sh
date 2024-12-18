#!/usr/bin/env bash

set -e

if ! type apt >& /dev/null; then
    echo "Error: package manager 'apt' is missing"
    exit 1
fi

install_dep () {
    DEP="$1"
    echo -n "$DEP: "

    # test if package exists

    if ! apt show "$DEP" >& /dev/null; then
        echo "failure"
        echo "Failed to locate $DEP"
        exit 1
    fi
    apt install -y "$DEP" >& /dev/null
    echo "success"
}

install_dep "libdata-printer-perl"
install_dep "libguestfs-perl"
install_dep "liblog-log4perl-perl"
install_dep "libengine-gost-openssl"
install_dep "liblogfile-rotate-perl"
