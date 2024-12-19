#!/usr/bin/env bash

set -ex

TMP_DIR="$(mktemp -d -p /tmp)"

echo "INFO: Working dir: $TMP_DIR"

if ! type git >& /dev/null; then
    echo "INFO: git is not installed"
    echo "INFO: installing..."
    apt install -y git
fi

if ! type mk-build-deps >& /dev/null; then
    echo "INFO: debian helpers scripts are not installed"
    echo "INFO: installing..."
    apt install -y devscripts
fi

pushd "$TMP_DIR" || exit 1

patch_component () {

    COMP="$1"
    echo "INFO: Patching component: $COMP"

    git clone -b pve-ic-support --depth 1 "https://github.com/zuxigit/$COMP"

    pushd "$COMP" || exit 1

    # apt tool may ask for confirmation
    mk-build-deps --install
    if [ -d 'src' ]; then
        pushd src || exit 1
        make install
        popd || exit 1
    else
        make install
    fi

    popd || exit 1
}

patch_component "pve-qemu-server"
patch_component "pve-cluster"

popd || exit 1
