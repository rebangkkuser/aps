#!/system/bin/sh

dir="/data/local/aps"
repo_dir="$dir/repos"
pkg_dir="$dir/pkgs"
tmp_dir="/data/local/tmp/aps"

repo="https://raw.githubusercontent.com/rebangkkuser/aps/main/main"
index="$repo/index"
index_name="$repo/indexName"

mkdir -p "$repo_dir" "$pkg_dir" 2>/dev/null
mkdir "$tmp_dir" 2>/dev/null

if [ ! -f "$repo_dir/main.alist" ] || [ "$(cat "$repo_dir/main.alist" 2>/dev/null)" != "$repo" ]; then
    echo "$repo" > "$repo_dir/main.alist"
fi


normalize_name() {
    echo "$1" |
        tr '[:upper:]' '[:lower:]' |
        tr -d '\r' |
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}


valid_name() {
    name="$1"

    case "$name" in
        ""|.|..|*[!a-z0-9._-]*)
            return 1
            ;;
    esac

    return 0
}


package_exists_in_index() {
    package="$1"

    grep -Fxq "$package" "$tmp_dir/index"
}


update_index() {
    echo "updating index..."

    index_tmp="$tmp_dir/index"
    index_name_tmp="$tmp_dir/indexName"

    rm -f "$index_tmp" "$index_name_tmp"

    curl -fsSL "$index" -o "$index_tmp" || {
        echo "error: failed to download index."
        return 1
    }

    curl -fsSL "$index_name" -o "$index_name_tmp" || {
        echo "error: failed to download indexName."
        rm -f "$index_tmp" "$index_name_tmp"
        return 1
    }

    [ -s "$index_tmp" ] || {
        echo "error: index is empty."
        rm -f "$index_tmp" "$index_name_tmp"
        return 1
    }

    [ -s "$index_name_tmp" ] || {
        echo "error: indexName is empty."
        rm -f "$index_tmp" "$index_name_tmp"
        return 1
    }

    rm -rf "$pkg_dir"
    mkdir -p "$pkg_dir" 2>/dev/null

    while IFS='=' read -r name package rest; do
        name="$(normalize_name "$name")"
        package="$(echo "$package" |
            tr -d '\r' |
            sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

        [ -z "$name" ] && continue
        [ -z "$package" ] && continue

        case "$name" in
            \#*)
                continue
                ;;
        esac

        if [ -n "$rest" ]; then
            echo "warning: invalid entry: $name = $package"
            continue
        fi

        if ! valid_name "$name"; then
            echo "warning: invalid application name: $name"
            continue
        fi

        case "$package" in
            *[!a-zA-Z0-9._-]*|"")
                echo "warning: invalid package: $package"
                continue
                ;;
        esac

        if ! package_exists_in_index "$package"; then
            echo "warning: package '$package' is not present in index."
            continue
        fi

        mkdir -p "$pkg_dir/$name" 2>/dev/null
        echo "$package" > "$pkg_dir/$name/package"
    done < "$index_name_tmp"

    rm -f "$index_tmp" "$index_name_tmp"

    echo "index updated."
}


find_package() {
    name="$(normalize_name "$1")"

    if ! valid_name "$name"; then
        return 1
    fi

    file="$pkg_dir/$name/package"

    if [ ! -f "$file" ]; then
        return 1
    fi

    package="$(cat "$file" 2>/dev/null)"

    if [ -z "$package" ]; then
        return 1
    fi

    echo "$package"
}


ensure_package() {
    name="$1"

    package="$(find_package "$name")"

    if [ -n "$package" ]; then
        echo "$package"
        return 0
    fi

    echo "application '$name' not found in local index."
    echo "updating index..."

    update_index || return 1

    package="$(find_package "$name")"

    if [ -z "$package" ]; then
        echo "error: application '$name' not found."
        return 1
    fi

    echo "$package"
}


download_apk() {
    name="$1"
    package="$2"

    download_file="$repo/pkg/$name/download"
    apk="$tmp_dir/$name.apk"
    url_file="$tmp_dir/$name.url"

    rm -f "$apk" "$url_file"

    curl -fsSL "$download_file" -o "$url_file" || {
        echo "error: failed to retrieve download url for $name."
        rm -f "$url_file"
        return 1
    }

    url="$(cat "$url_file" 2>/dev/null)"

    rm -f "$url_file"

    url="$(echo "$url" |
        tr -d '\r' |
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    [ -n "$url" ] || {
        echo "error: download url is empty."
        return 1
    }

    echo "downloading $name..."

    curl -fL "$url" -o "$apk" || {
        echo "error: failed to download apk."
        rm -f "$apk"
        return 1
    }

    [ -s "$apk" ] || {
        echo "error: downloaded apk is empty."
        rm -f "$apk"
        return 1
    }

    echo "$apk"
}


install_package() {
    name="$1"
    package="$2"

    apk="$(download_apk "$name" "$package")" || {
        return 1
    }

    echo "installing $name ($package)..."

    pm install "$apk"
    result=$?

    rm -f "$apk"

    if [ "$result" -ne 0 ]; then
        echo "error: installation failed."
        return "$result"
    fi

    echo "installation successful."

    return 0
}


is_installed() {
    package="$1"

    pm list packages 2>/dev/null |
        grep -Fxq "package:$package"
}


case "$1" in

    update)
        update_index
        ;;

    install)
        if [ -z "$2" ]; then
            echo "usage: $0 install <name>"
            exit 1
        fi

        name="$(normalize_name "$2")"

        if ! valid_name "$name"; then
            echo "error: invalid application name."
            exit 1
        fi

        package="$(ensure_package "$name")" || exit 1

        echo "installing $name ($package)..."

        install_package "$name" "$package"
        ;;

    uninstall|remove)
        if [ -z "$2" ]; then
            echo "usage: $0 uninstall <name>"
            exit 1
        fi

        name="$(normalize_name "$2")"

        if ! valid_name "$name"; then
            echo "error: invalid application name."
            exit 1
        fi

        package="$(ensure_package "$name")" || exit 1

        if ! is_installed "$package"; then
            echo "error: $name is not installed."
            exit 1
        fi

        echo "uninstalling $name ($package)..."

        pm uninstall "$package"
        result=$?

        if [ "$result" -ne 0 ]; then
            echo "error: uninstallation failed."
            exit "$result"
        fi

        echo "uninstallation successful."
        ;;

    reinstall)
        if [ -z "$2" ]; then
            echo "usage: $0 reinstall <name>"
            exit 1
        fi

        name="$(normalize_name "$2")"

        if ! valid_name "$name"; then
            echo "error: invalid application name."
            exit 1
        fi

        package="$(ensure_package "$name")" || exit 1

        if is_installed "$package"; then
            echo "uninstalling $name ($package)..."

            pm uninstall "$package"
            result=$?

            if [ "$result" -ne 0 ]; then
                echo "error: uninstallation failed."
                exit "$result"
            fi
        else
            echo "$name is not currently installed."
        fi

        echo "reinstalling $name ($package)..."

        install_package "$name" "$package"
        ;;

    *)
        echo "usage:"
        echo "  $0 update"
        echo "  $0 install <name>"
        echo "  $0 uninstall <name>"
        echo "  $0 reinstall <name>"
        exit 1
        ;;

esac
