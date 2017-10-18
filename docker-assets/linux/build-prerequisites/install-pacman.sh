#!/bin/bash

set -ex

patch_config_sub() {
	local filename="$1"
	mv "${filename}"{,.orig}
	cat > "${filename}" <<'EOF'
#!/bin/bash
if [[ $1 == "x86_64-redhat-linux" ]]; then
	echo "x86_64-redhat-linux"
	exit 0
fi
exec "$0.orig" "$@"
EOF
	chmod a+x "${filename}"
}

cd $(dirname ${BASH_SOURCE})

mkdir pacman-build
pushd pacman-build

curl https://sources.archlinux.org/other/pacman/pacman-5.0.2.tar.gz | tar xz
cd pacman-5.0.2
patch_config_sub build-aux/config.sub
./configure --{build,host}="x86_64-redhat-linux"
make
make install

popd
rm -rf pacman-build
