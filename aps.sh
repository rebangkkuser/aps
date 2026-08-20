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

mkdir -p "$repo_dir" "$pkg_dir" "$tmp_dir" 2>/dev/null

if [ "$(cat "$repo_dir/main.alist" 2>/dev/null)" != "$repo" ]; then
    echo "$repo" > "$repo_dir/main.alist"
fi

if [ -t 1 ]; then
    RED="$(printf '\033[31m')"
    GREEN="$(printf '\033[32m')"
    YELLOW="$(printf '\033[33m')"
    BLUE="$(printf '\033[34m')"
    CYAN="$(printf '\033[36m')"
    RESET="$(printf '\033[0m')"
else
    RED=""; GREEN=""; YELLOW=""; BLUE=""
    CYAN=""; RESET=""
fi

AUTO_YES=0
DHASH=0

normalize_name() {
    echo "$1" |
        tr '[:upper:]' '[:lower:]' |
        tr -d '\r' |
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

valid_name() {
    case "$1" in
        ""|.|..|*[!a-z0-9._-]*) return 1 ;;
    esac
    return 0
}

is_installed() {
    pm list packages 2>/dev/null |
        grep -Fxq "package:$1"
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

    if [ -n "$package" ]; then
        echo "$package"
        return 0
    fi

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
        return 1
    }

    download_index "$index_deps" "$tmp_dir/indexOfDeps" 2>/dev/null || :
    download_index "$index_breaks" "$tmp_dir/indexOfBreaks" 2>/dev/null || :
    download_index "$index_hashes" "$tmp_dir/indexOfhashes" 2>/dev/null || :

    rm -rf "$pkg_dir"
    mkdir -p "$pkg_dir"

    while IFS='=' read -r name package rest; do
        name="$(normalize_name "$name")"
        package="$(echo "$package" |
            tr -d '\r' |
            sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

        [ -z "$name" ] && continue
        [ -z "$package" ] && continue

        case "$name" in
            \#*) continue ;;
        esac

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

deps_for() {
    grep '^app "'"$1"'" deps ' "$tmp_dir/indexOfDeps" 2>/dev/null |
        head -n 1 |
        sed 's/^.* deps //'
}

breaks_for() {
    grep '^'"$1"' = breaks with ' "$tmp_dir/indexOfBreaks" 2>/dev/null |
        head -n 1 |
        sed 's/^.*breaks with //'
}

hash_for() {
    grep '^application "'"$1"'" sha256 ' "$tmp_dir/indexOfhashes" 2>/dev/null |
        head -n 1 |
        sed 's/^.*sha256 //'
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

    [ "$DHASH" -eq 1 ] && {
        echo "${YELLOW}SHA-256 verification skipped (--dhash).${RESET}"
        return 0
    }

    expected="$(hash_for "$name")"

    [ -n "$expected" ] || {
        echo "${RED}error: no SHA-256 hash found for '$name'.${RESET}"
        echo "${RED}installation refused. Use --dhash to bypass.${RESET}"
        return 1
    }

    command -v sha256sum >/dev/null 2>&1 || {
        echo "${RED}error: sha256sum is unavailable.${RESET}"
        echo "${RED}installation refused. Use --dhash to bypass.${RESET}"
        return 1
    }

    actual="$(sha256sum "$apk" 2>/dev/null | awk '{print $1}')"

    if [ -z "$actual" ] || [ "$actual" != "$expected" ]; then
        echo "${RED}error: SHA-256 verification failed.${RESET}"
        echo "expected: $expected"
        echo "actual:   ${actual:-unavailable}"
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

    url="$(cat "$url_file" 2>/dev/null |
        tr -d '\r' |
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

install_package() {
    name="$1"
    package="$2"

    check_breaks "$name" || return 1
    check_deps "$name" "" || return 1

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

    echo "package: $package"

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
        package="$(echo "$package" |
            tr -d '\r' |
            sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

        echo "$name $package" | grep -Fqi "$term" || continue

        printf '%s  %s\n' "$name" "$package"
        found=1
    done < "$tmp_dir/indexName"

    [ "$found" -eq 1 ] || echo "no applications found."
}

list_packages() {
    [ -s "$tmp_dir/indexName" ] || update_index || return 1

    while IFS='=' read -r name package rest; do
        name="$(normalize_name "$name")"
        package="$(echo "$package" |
            tr -d '\r' |
            sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

        [ -n "$name" ] || continue
        [ -n "$package" ] || continue

        if is_installed "$package"; then
            echo "$name ($package)"
        fi
    done < "$tmp_dir/indexName"
}

info() {
    name="$(normalize_name "$1")"
    package="$(ensure_package "$name")" || return 1

    echo "name: $name"
    echo "package: $package"

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

reinstall() {
    name="$(normalize_name "$1")"
    package="$(ensure_package "$name")" || return 1

    if is_installed "$package"; then
        confirm "uninstall $name before reinstalling?" || return 0
        pm uninstall "$package" || return 1
    fi

    install_package "$name" "$package"
}

clean() {
    find "$tmp_dir" -type f \
        \( -name '*.apk' -o -name '*.url' \) \
        -delete 2>/dev/null

    echo "${GREEN}APS cache cleaned.${RESET}"
}

usage() {
    echo "usage:"
    echo "  $0 update"
    echo "  $0 search <term>"
    echo "  $0 info <name>"
    echo "  $0 list"
    echo "  $0 install|ins|get <name> [-y] [--dhash]"
    echo "  $0 insy <name> [--dhash]"
    echo "  $0 download|dl <name> [--dhash]"
    echo "  $0 remove|rm|del <name> [-y]"
    echo "  $0 rmy <name>"
    echo "  $0 reinstall <name> [-y] [--dhash]"
    echo "  $0 clean"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -y) AUTO_YES=1 ;;
        --dhash) DHASH=1 ;;
        *) break ;;
    esac
    shift
done

command="$1"
[ "$#" -gt 0 ] && shift

case "$command" in
    update)
        update_index
        ;;

    search)
        search "$1"
        ;;

    info)
        [ -n "$1" ] || {
            echo "usage: $0 info <name>"
            exit 1
        }
        [ -s "$tmp_dir/indexName" ] || update_index || exit 1
        info "$1"
        ;;

    list)
        list_packages
        ;;

    install|ins|get)
        [ -n "$1" ] || {
            echo "usage: $0 install <name> [-y] [--dhash]"
            exit 1
        }
        [ -s "$tmp_dir/indexName" ] || update_index || exit 1
        do_install "$1"
        ;;

    insy)
        [ -n "$1" ] || {
            echo "usage: $0 insy <name> [--dhash]"
            exit 1
        }
        AUTO_YES=1
        [ -s "$tmp_dir/indexName" ] || update_index || exit 1
        do_install "$1"
        ;;

    download|dl)
        [ -n "$1" ] || {
            echo "usage: $0 download <name> [--dhash]"
            exit 1
        }
        [ -s "$tmp_dir/indexName" ] || update_index || exit 1
        download_only "$1"
        ;;

    remove|rm|del|uninstall)
        [ -n "$1" ] || {
            echo "usage: $0 remove <name> [-y]"
            exit 1
        }
        [ -s "$tmp_dir/indexName" ] || update_index || exit 1
        remove_package "$1"
        ;;

    rmy)
        [ -n "$1" ] || {
            echo "usage: $0 rmy <name>"
            exit 1
        }
        AUTO_YES=1
        [ -s "$tmp_dir/indexName" ] || update_index || exit 1
        remove_package "$1"
        ;;

    reinstall)
        [ -n "$1" ] || {
            echo "usage: $0 reinstall <name> [-y] [--dhash]"
            exit 1
        }
        [ -s "$tmp_dir/indexName" ] || update_index || exit 1
        reinstall "$1"
        ;;

    clean)
        clean
        ;;

    *)
        usage
        exit 1
        ;;
esac
