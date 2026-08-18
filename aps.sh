#!/system/bin/sh

dir="/data/local/aps"
repo_dir="$dir/repos"
pkg_dir="$dir/pkgs"
tmp_dir="/tmp/aps"

repo="https://raw.githubusercontent.com/rebangkkuser/aps/main/main"
index="$repo/index"
index_name="$repo/indexName"

mkdir -p "$repo_dir" "$pkg_dir" 2>/dev/null
mkdir "$tmp_dir" 2>/dev/null

if [ ! -f "$repo_dir/main.alist" ] || [ "$(cat "$repo_dir/main.alist" 2>/dev/null)" != "$repo" ]; then
    echo "$repo" > "$repo_dir/main.alist"
fi


update_index() {
    echo "updating index..."

    index_tmp="$tmp_dir/index"
    index_name_tmp="$tmp_dir/indexName"

    curl -fsSL "$index" -o "$index_tmp" || {
        echo "error: failed to download index."
        return 1
    }

    curl -fsSL "$index_name" -o "$index_name_tmp" || {
        echo "error: failed to download indexName."
        return 1
    }

    rm -rf "$pkg_dir"
    mkdir -p "$pkg_dir" 2>/dev/null

    while IFS='=' read -r name package; do
        name="$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        package="$(echo "$package" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

        [ -z "$name" ] && continue
        [ -z "$package" ] && continue

        mkdir -p "$pkg_dir/$name" 2>/dev/null
        echo "$package" > "$pkg_dir/$name/package"
    done < "$index_name_tmp"

    rm -f "$index_tmp" "$index_name_tmp"

    echo "index updated."
}


find_package() {
    name="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
    file="$pkg_dir/$name/package"

    if [ ! -f "$file" ]; then
        echo "error: application '$name' not found."
        echo "run '$0 update' first."
        return 1
    fi

    cat "$file"
}


install_package() {
    package="$1"

    download_file="$repo/pkg/$package/download"
    apk="$tmp_dir/$package.apk"

    url="$(curl -fsSL "$download_file")" || {
        echo "error: failed to retrieve the download url."
        return 1
    }

    echo "downloading $package..."

    curl -fL "$url" -o "$apk" || {
        echo "error: failed to download the apk."
        rm -f "$apk"
        return 1
    }

    echo "installing $package..."

    pm install "$apk"

    result=$?

    rm -f "$apk"

    return $result
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

        name="$(echo "$2" | tr '[:upper:]' '[:lower:]')"
        package="$(find_package "$name")" || exit 1

        echo "installing $name ($package)..."

        install_package "$package"
        ;;

    uninstall|remove)
        if [ -z "$2" ]; then
            echo "usage: $0 uninstall <name>"
            exit 1
        fi

        name="$(echo "$2" | tr '[:upper:]' '[:lower:]')"
        package="$(find_package "$name")" || exit 1

        echo "uninstalling $name ($package)..."

        pm uninstall "$package"
        ;;

    reinstall)
        if [ -z "$2" ]; then
            echo "usage: $0 reinstall <name>"
            exit 1
        fi

        name="$(echo "$2" | tr '[:upper:]' '[:lower:]')"
        package="$(find_package "$name")" || exit 1

        echo "uninstalling $name ($package)..."

        pm uninstall "$package" >/dev/null 2>&1

        echo "reinstalling $name ($package)..."

        install_package "$package"
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
