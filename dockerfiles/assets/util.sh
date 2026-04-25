#!/bin/bash
set -exuo pipefail

github_curl() {
  if [ -r /run/secrets/github_token ]; then
    curl -sSL -H "Authorization: Bearer $(cat /run/secrets/github_token)" "$@"
  else
    curl -sSL "$@"
  fi
}

get_github_release() {
  local github_project=$1
  local asset=${2-}
  local version_regex=${3:-"\([0-9]\+\.[0-9]\+\.[0-9]\+\)$"}

  local tag=""
  local page=1
  while [ "$page" -le 20 ]; do
    local names
    names=$(
      github_curl "https://api.github.com/repos/$github_project/tags?per_page=100&page=$page" \
        | grep '^\s\+"name":' \
        | sed 's/\s\+"name": \"\(.*\)\".*/\1/' \
        || true
    )
    if [ -z "$names" ]; then
      break
    fi
    local match
    match=$(printf '%s\n' "$names" | { grep "$version_regex" || true; } | sort -V | tail -1)
    if [ -n "$match" ]; then
      tag=$match
      break
    fi
    page=$((page + 1))
  done

  if [ -z "$tag" ]; then
    echo "ERROR: no tag in $github_project matching '$version_regex'" >&2
    return 1
  fi

  curl -sSL "$(
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
