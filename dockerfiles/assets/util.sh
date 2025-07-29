#!/bin/bash
set -exuo pipefail

get_github_release() {
  local github_project=$1
  local asset=${2-}
  local version_regex=${3:-"\([0-9]\+\.[0-9]\+\.[0-9]\+\)$"}

  local tag; tag=$(
    curl -sL "https://api.github.com/repos/$github_project/tags" \
      | grep '^\s\+"name":' | sed 's/\s\+"name": \"\(.*\)\".*/\1/' \
      | grep "$version_regex" | sort -V | tail -1
  )

  curl -sL "$(
    if [ -n "$asset" ]; then
      version=$(
        # shellcheck disable=SC2001
        echo "$tag" | sed "s/.*$version_regex/\1/"
      )
      echo "https://github.com/$github_project/releases/download/$tag/${asset//\%v\%/$version}"
    else
      echo "https://github.com/$github_project/archive/refs/tags/$tag.tar.gz"
    fi
  )"
}

switch_centos_to_vault_repos() {
  local centos_version
  centos_version=$(
    eval "$(cat /etc/os-release)"
    echo "$VERSION_ID"
  )

  sed -i /etc/yum.repos.d/*.repo \
    -e 's/mirror.centos.org/vault.centos.org/g' \
    -e '/mirrorlist.centos.org/d' \
    -e 's/^#\(baseurl=.*\)/\1/g' \
    -e 's/http:/https:/g'

  if [ "$(uname -m)" = aarch64 ]; then
    sed -i "s|vault.centos.org/centos/$centos_version/sclo|` \
      `vault.centos.org/altarch/$centos_version/sclo|g" /etc/yum.repos.d/*.repo; \
  fi
}

get_latest_gnu_version() {
  local latest_version
  apt-get update > /dev/null
  latest_version=$( \
    apt-cache search '^g\+\+-[0-9]+$' \
    | cut -d- -f2 \
    | tr -d ' ' \
    | sort -nr \
    | head -n1 \
  )
  apt-get clean
  rm -rf /var/lib/apt/lists/*
  echo "$latest_version"
}

yum_install_clean() {
  yum -y update
  yum -y install "$@"
  yum clean all
  rm -rf /var/cache/yum/*
}

"$@"
