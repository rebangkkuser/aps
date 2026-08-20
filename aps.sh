#!/system/bin/sh

dir="/data/local/aps"
repo_dir="$dir/repos"
pkg_dir="$dir/pkgs"
tmp_dir="/data/local/tmp/aps"

repo="https://raw.githubusercontent.com/rebangkkuser/aps/main/main"
index="$repo/index"
index_name="$repo/indexName"
index_deps="$repo/indexOfDeps"
index_breaks="$repo/indexOfBreaks"
index_hashes="$repo/indexOfhashes"
index_ver="$repo/verIndex"

mkdir -p "$repo_dir" "$pkg_dir" "$tmp_dir" 2>/dev/null

if [ "$(cat "$repo_dir/main.alist" 2>/dev/null)" != "$repo" ]; then
    echo "$repo" > "$repo_dir/main.alist"
fi

if [ -t 1 ]; then
    RED="$(printf '\033[31m')"
    GREEN="$(printf '\033[32m')"
    YELLOW="$(printf '\033[33m')"
    BLUE="$(printf '\033[34m')"
    MAGENTA="$(printf '\033[35m')"
    CYAN="$(printf '\033[36m')"
    RESET="$(printf '\033[0m')"
else
    RED=""; GREEN=""; YELLOW=""; BLUE=""
    MAGENTA=""; CYAN=""; RESET=""
fi

AUTO_YES=0

normalize_name() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr -d '\r' |
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

valid_name() {
    case "$1" in
        ""|.|..|*[!a-z0-9._-]*) return 1 ;;
    esac
    return 0
}

is_installed() {
    pm list packages 2>/dev/null | grep -Fxq "package:$1"
}

package_exists_in_index() {
    grep -Fxq "$1" "$tmp_dir/index" 2>/dev/null
}

find_package() {
    name="$(normalize_name "$1")"
    valid_name "$name" || return 1

    file="$pkg_dir/$name/package"
    [ -f "$file" ] || return 1

    package="$(cat "$file" 2>/dev/null)"
    [ -n "$package" ] && echo "$package"
}

ensure_package() {
    package="$(find_package "$1")"
    [ -n "$package" ] && {
        echo "$package"
        return 0
    }

    echo "application '$1' not found in local index." >&2
    echo "updating index..." >&2

    update_index || return 1
    package="$(find_package "$1")"

    [ -n "$package" ] || {
        echo "error: application '$1' not found." >&2
        return 1
    }

    echo "$package"
}

download_index() {
    url="$1"
    file="$2"

    rm -f "$file"
    curl -fsSL "$url" -o "$file" || return 1
    [ -s "$file" ]
}

update_index() {
    echo "updating index..."

    download_index "$index" "$tmp_dir/index" || {
        echo "error: failed to download index."
        return 1
    }

    download_index "$index_name" "$tmp_dir/indexName" || {
        echo "error: failed to download indexName."
        rm -f "$tmp_dir/index"
        return 1
    }

    download_index "$index_deps" "$tmp_dir/indexOfDeps" 2>/dev/null || :
    download_index "$index_breaks" "$tmp_dir/indexOfBreaks" 2>/dev/null || :
    download_index "$index_hashes" "$tmp_dir/indexOfhashes" 2>/dev/null || :
    download_index "$index_ver" "$tmp_dir/verIndex" 2>/dev/null || :

    rm -rf "$pkg_dir"
    mkdir -p "$pkg_dir"

    while IFS='=' read -r name package rest; do
        name="$(normalize_name "$name")"
        package="$(echo "$package" | tr -d '\r' |
            sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

        [ -z "$name" ] && continue
        [ -z "$package" ] && continue

        case "$name" in \#*) continue ;; esac
        [ -z "$rest" ] || {
            echo "warning: invalid entry: $name = $package"
            continue
        }

        valid_name "$name" || {
            echo "warning: invalid application name: $name"
            continue
        }

        case "$package" in
            *[!a-zA-Z0-9._-]*)
                echo "warning: invalid package: $package"
                continue
                ;;
        esac

        package_exists_in_index "$package" || {
            echo "warning: package '$package' is not present in index."
            continue
        }

        mkdir -p "$pkg_dir/$name"
        echo "$package" > "$pkg_dir/$name/package"
    done < "$tmp_dir/indexName"

    echo "index updated."
}

line_value() {
    file="$1"
    pattern="$2"

    grep -F "$pattern" "$file" 2>/dev/null |
        head -n 1 |
        sed "s/.*$pattern//"
}

deps_for() {
    grep '^app "'"$1"'" deps ' "$tmp_dir/indexOfDeps" 2>/dev/null |
        head -n 1 | sed 's/^.* deps //'
}

breaks_for() {
    grep '^'"$1"' = breaks with ' "$tmp_dir/indexOfBreaks" 2>/dev/null |
        head -n 1 | sed 's/^.*breaks with //'
}

hash_for() {
    grep '^application "'"$1"'" sha256 ' "$tmp_dir/indexOfhashes" 2>/dev/null |
        head -n 1 | sed 's/^.*sha256 //'
}

version_for() {
    grep '^'"$1"' = ' "$tmp_dir/verIndex" 2>/dev/null |
        head -n 1 | sed 's/^.*= //'
}

release_type() {
    case "$1" in
        *nightly*) echo nightly ;;
        *alpha*) echo alpha ;;
        *beta*) echo beta ;;
        *-rc*) echo rc ;;
        *) echo stable ;;
    esac
}

release_label() {
    case "$(release_type "$1")" in
        stable) echo "${GREEN}stable${RESET}" ;;
        rc) echo "${YELLOW}rc${RESET}" ;;
        beta) echo "${YELLOW}beta${RESET}" ;;
        alpha) echo "${RED}alpha${RESET}" ;;
        nightly) echo "${MAGENTA}nightly${RESET}" ;;
    esac
}

version_key() {
    v="$1"
    type="$(release_type "$v")"

    base="$(echo "$v" | sed 's/-nightly.*//;s/-alpha.*//;s/-beta.*//;s/-rc.*//')"

    IFS='.' read -r a b c rest <<EOF
$base
EOF

    a="${a:-0}"; b="${b:-0}"; c="${c:-0}"

    case "$type" in
        alpha) r=1 ;;
        beta) r=2 ;;
        rc) r=3 ;;
        stable) r=4 ;;
        nightly) r=0 ;;
    esac

    suffix="$(echo "$v" | sed 's/^[^-]*//' | tr -cd '0-9')"
    suffix="${suffix:-0}"

    printf '%08d%08d%08d%02d%08d\n' "$a" "$b" "$c" "$r" "$suffix"
}

version_newer() {
    [ "$(version_key "$1")" -gt "$(version_key "$2")" ]
}

confirm() {
    [ "$AUTO_YES" -eq 1 ] && return 0

    printf '%s [y/N] ' "$1"
    read answer

    case "$answer" in
        y|Y|yes|YES) return 0 ;;
    esac

    return 1
}

check_deps() {
    name="$1"
    stack="$2"

    case " $stack " in
        *" $name "*) 
            echo "${RED}error: circular dependency detected: $stack $name${RESET}"
            return 1
            ;;
    esac

    for dep in $(deps_for "$name"); do
        [ -n "$dep" ] || continue

        dep_package="$(find_package "$dep")"

        [ -n "$dep_package" ] || {
            echo "${RED}error: dependency '$dep' not found.${RESET}"
            return 1
        }

        if ! is_installed "$dep_package"; then
            check_deps "$dep" "$stack $name" || return 1
        fi
    done
}

check_breaks() {
    name="$1"

    for conflict in $(breaks_for "$name"); do
        package="$(find_package "$conflict")"

        if [ -n "$package" ] && is_installed "$package"; then
            echo "${RED}error: $name breaks with $conflict.${RESET}"
            return 1
        fi
    done

    return 0
}

verify_hash() {
    name="$1"
    apk="$2"
    expected="$(hash_for "$name")"

    [ -z "$expected" ] && return 0

    command -v sha256sum >/dev/null 2>&1 || {
        echo "${YELLOW}warning: sha256sum is unavailable; skipping verification.${RESET}"
        return 0
    }

    actual="$(sha256sum "$apk" 2>/dev/null | awk '{print $1}')"

    if [ "$actual" != "$expected" ]; then
        echo "${RED}error: SHA-256 verification failed.${RESET}"
        echo "expected: $expected"
        echo "actual:   $actual"
        return 1
    fi

    echo "${GREEN}SHA-256 verified.${RESET}"
}

download_apk() {
    name="$1"
    package="$2"

    download_file="$repo/pkg/$name/download"
    apk="$tmp_dir/$name.apk"
    url_file="$tmp_dir/$name.url"

    rm -f "$apk" "$url_file"

    curl -fsSL "$download_file" -o "$url_file" || {
        echo "error: failed to retrieve download url for $name." >&2
        return 1
    }

    url="$(cat "$url_file" 2>/dev/null | tr -d '\r' |
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    rm -f "$url_file"

    [ -n "$url" ] || {
        echo "error: download url is empty." >&2
        return 1
    }

    echo "downloading $name..." >&2

    curl -fL "$url" -o "$apk" || {
        echo "error: failed to download apk." >&2
        rm -f "$apk"
        return 1
    }

    [ -s "$apk" ] || {
        echo "error: downloaded apk is empty." >&2
        rm -f "$apk"
        return 1
    }

    echo "$apk"
}

download_only() {
    name="$(normalize_name "$1")"
    valid_name "$name" || {
        echo "error: invalid application name."
        return 1
    }

    package="$(ensure_package "$name")" || return 1
    apk="$(download_apk "$name" "$package")" || return 1

    verify_hash "$name" "$apk" || {
        rm -f "$apk"
        return 1
    }

    echo "downloaded: $apk"
}

install_package() {
    name="$1"
    package="$2"

    check_breaks "$name" || return 1
    check_deps "$name" "$stack" || return 1

    for dep in $(deps_for "$name"); do
        dep_package="$(find_package "$dep")"
        [ -n "$dep_package" ] || continue

        if ! is_installed "$dep_package"; then
            echo "installing dependency $dep ($dep_package)..."
            install_package "$dep" "$dep_package" || return 1
        fi
    done

    apk="$(download_apk "$name" "$package")" || return 1

    verify_hash "$name" "$apk" || {
        rm -f "$apk"
        return 1
    }

    echo "installing $name ($package)..."

    pm install "$apk"
    result=$?

    rm -f "$apk"

    [ "$result" -eq 0 ] || {
        echo "error: installation failed."
        return "$result"
    }

    echo "${GREEN}installation successful.${RESET}"
}

do_install() {
    name="$(normalize_name "$1")"
    valid_name "$name" || {
        echo "error: invalid application name."
        return 1
    }

    package="$(ensure_package "$name")" || return 1

    if is_installed "$package"; then
        echo "${YELLOW}$name is already installed.${RESET}"
        return 0
    fi

    version="$(version_for "$name")"

    echo "package: $package"
    [ -n "$version" ] && echo "version: $version ($(release_label "$version"))"

    deps="$(deps_for "$name")"
    [ -n "$deps" ] && echo "dependencies: $deps"

    breaks="$(breaks_for "$name")"
    [ -n "$breaks" ] && echo "breaks with: $breaks"

    confirm "install $name?" || {
        echo "installation cancelled."
        return 0
    }

    install_package "$name" "$package"
}

remove_package() {
    name="$(normalize_name "$1")"
    package="$(ensure_package "$name")" || return 1

    is_installed "$package" || {
        echo "${YELLOW}$name is not installed.${RESET}"
        return 1
    }

    confirm "uninstall $name?" || {
        echo "uninstallation cancelled."
        return 0
    }

    echo "uninstalling $name ($package)..."

    pm uninstall "$package"
    result=$?

    [ "$result" -eq 0 ] || {
        echo "error: uninstallation failed."
        return "$result"
    }

    echo "${GREEN}uninstallation successful.${RESET}"
}

search() {
    term="$(normalize_name "$1")"

    [ -n "$term" ] || {
        echo "usage: $0 search <term>"
        return 1
    }

    [ -s "$tmp_dir/indexName" ] || update_index || return 1

    found=0

    while IFS='=' read -r name package rest; do
        name="$(normalize_name "$name")"
        package="$(echo "$package" | tr -d '\r' |
            sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

        echo "$name $package" | grep -Fqi "$term" || continue

        version="$(version_for "$name")"

        printf '%s' "$name"
        [ -n "$version" ] && printf '  %s  [%s]' "$version" "$(release_label "$version")"
        printf '\n  %s\n' "$package"

        found=1
    done < "$tmp_dir/indexName"

    [ "$found" -eq 1 ] || echo "no applications found."
}

list_packages() {
    [ -s "$tmp_dir/indexName" ] || update_index || return 1

    while IFS='=' read -r name package rest; do
        name="$(normalize_name "$name")"
        package="$(echo "$package" | tr -d '\r' |
            sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

        [ -n "$name" ] || continue
        [ -n "$package" ] || continue

        if is_installed "$package"; then
            version="$(version_for "$name")"
            printf '%s' "$name"
            [ -n "$version" ] && printf '  %s' "$version"
            printf '\n'
        fi
    done < "$tmp_dir/indexName"
}

info() {
    name="$(normalize_name "$1")"
    package="$(ensure_package "$name")" || return 1

    version="$(version_for "$name")"

    echo "name: $name"
    echo "package: $package"
    [ -n "$version" ] && echo "version: $version ($(release_label "$version"))"

    deps="$(deps_for "$name")"
    breaks="$(breaks_for "$name")"
    hash="$(hash_for "$name")"

    [ -n "$deps" ] && echo "dependencies: $deps"
    [ -n "$breaks" ] && echo "breaks with: $breaks"
    [ -n "$hash" ] && echo "sha256: $hash"

    if is_installed "$package"; then
        echo "status: installed"
    else
        echo "status: not installed"
    fi
}

upgrade() {
    [ -s "$tmp_dir/indexName" ] || update_index || return 1

    upgrades="$tmp_dir/upgrades"
    : > "$upgrades"

    while IFS='=' read -r name package rest; do
        name="$(normalize_name "$name")"
        package="$(echo "$package" | tr -d '\r' |
            sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

        [ -n "$name" ] || continue
        [ -n "$package" ] || continue
        is_installed "$package" || continue

        current="$(dumpsys package "$package" 2>/dev/null |
            sed -n 's/^[[:space:]]*versionName=\([^[:space:]]*\).*/\1/p' | head -n 1)"
        available="$(version_for "$name")"

        [ -n "$current" ] || continue
        [ -n "$available" ] || continue

        if version_newer "$available" "$current"; then
            echo "$name|$package|$current|$available" >> "$upgrades"
        fi
    done < "$tmp_dir/indexName"

    [ -s "$upgrades" ] || {
        echo "${GREEN}all packages are up to date.${RESET}"
        return 0
    }

    echo "available upgrades:"
    while IFS='|' read -r name package current available; do
        echo "  $name: $current -> $available"
    done < "$upgrades"

    confirm "upgrade packages?" || {
        echo "upgrade cancelled."
        return 0
    }

    while IFS='|' read -r name package current available; do
        install_package "$name" "$package" || return 1
    done < "$upgrades"

    rm -f "$upgrades"
}

clean() {
    find "$tmp_dir" -type f \( -name '*.apk' -o -name '*.url' \) -delete 2>/dev/null
    echo "${GREEN}APS cache cleaned.${RESET}"
}

usage() {
    echo "usage:"
    echo "  $0 update"
    echo "  $0 search <term>"
    echo "  $0 info <name>"
    echo "  $0 list"
    echo "  $0 install|ins|get <name> [-y]"
    echo "  $0 insy <name>"
    echo "  $0 download|dl <name>"
    echo "  $0 remove|rm|del <name> [-y]"
    echo "  $0 rmy <name>"
    echo "  $0 reinstall <name> [-y]"
    echo "  $0 upgrade [-y]"
    echo "  $0 clean"
}

case "$1" in
    update)
        update_index
        ;;

    search)
        search "$2"
        ;;

    info)
        [ -n "$2" ] || {
            echo "usage: $0 info <name>"
            exit 1
        }
        [ -s "$tmp_dir/indexName" ] || update_index || exit 1
        info "$2"
        ;;

    list)
        list_packages
        ;;

    install|ins|get)
        [ -n "$2" ] || {
            echo "usage: $0 install <name> [-y]"
            exit 1
        }

        AUTO_YES=0
        [ "$3" = "-y" ] && AUTO_YES=1
        [ "$2" = "-y" ] && {
            echo "error: application name missing."
            exit 1
        }

        [ -s "$tmp_dir/indexName" ] || update_index || exit 1
        do_install "$2"
        ;;

    insy)
        [ -n "$2" ] || {
            echo "usage: $0 insy <name>"
            exit 1
        }

        AUTO_YES=1
        [ -s "$tmp_dir/indexName" ] || update_index || exit 1
        do_install "$2"
        ;;

    download|dl)
        [ -n "$2" ] || {
            echo "usage: $0 download <name>"
            exit 1
        }

        [ -s "$tmp_dir/indexName" ] || update_index || exit 1
        download_only "$2"
        ;;

    uninstall|remove|rm|del)
        [ -n "$2" ] || {
            echo "usage: $0 remove <name> [-y]"
            exit 1
        }

        AUTO_YES=0
        [ "$3" = "-y" ] && AUTO_YES=1
        [ -s "$tmp_dir/indexName" ] || update_index || exit 1
        remove_package "$2"
        ;;

    rmy)
        [ -n "$2" ] || {
            echo "usage: $0 rmy <name>"
            exit 1
        }

        AUTO_YES=1
        [ -s "$tmp_dir/indexName" ] || update_index || exit 1
        remove_package "$2"
        ;;

    reinstall)
        [ -n "$2" ] || {
            echo "usage: $0 reinstall <name> [-y]"
            exit 1
        }

        AUTO_YES=0
        [ "$3" = "-y" ] && AUTO_YES=1
        [ -s "$tmp_dir/indexName" ] || update_index || exit 1

        name="$(normalize_name "$2")"
        package="$(ensure_package "$name")" || exit 1

        if is_installed "$package"; then
            confirm "uninstall $name before reinstalling?" || exit 0
            pm uninstall "$package" || exit 1
        fi

        install_package "$name" "$package"
        ;;

    upgrade)
        AUTO_YES=0
        [ "$2" = "-y" ] && AUTO_YES=1
        upgrade
        ;;

    clean)
        clean
        ;;

    *)
        usage
        exit 1
        ;;
esac
