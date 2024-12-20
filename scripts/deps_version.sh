#!/usr/bin/bash

set -e

dep_version() {
    DEP="$1"
    echo -n "$DEP: "

    # test if package exists
    if ! apt show "$DEP" >& /dev/null; then
        echo "failure"
        echo "Failed to locate $DEP"
        exit 1
    fi
    apt-cache policy "$DEP" | grep Installed | awk -F' ' '{print $2}'
}

dep_version "libdata-printer-perl"
dep_version "libguestfs-perl"
dep_version "liblog-log4perl-perl"
dep_version "libengine-gost-openssl"
dep_version "liblogfile-rotate-perl"
