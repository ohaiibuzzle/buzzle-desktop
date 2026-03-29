#!/bin/bash

set_pkg_attrs() {
  local pkgname="$1"
  pacman -Qlq "$pkgname" | while read -r filepath; do
    if [[ -f "$filepath" ]]; then
       setfattr -n user.component -v "$pkgname" "$filepath" || true
    fi
  done
}

export -f set_pkg_attrs

pacman -Qq | parallel --bar set_pkg_attrs

# set all of /usr/opt to be owned by the "opt" component, it will be overlayed to /opt in the final image
find /usr/opt -type f -exec setfattr -n user.component -v "opt" {} \; || true