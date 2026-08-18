#!/system/bin/sh

DIR="/data/local/aps"
REPO_DIR="$DIR/repos"
TMP_DIR="/tmp/aps"

REPO="https://raw.githubusercontent.com/rebangkkuser/aps/main/main/pkg"

mkdir -p "$REPO_DIR" "$TMP_DIR"

if [ ! -f "$REPO_DIR/main.alist" ] || [ "$(cat "$REPO_DIR/main.alist")" != "$REPO" ]; then
    echo "$REPO" > "$REPO_DIR/main.alist"
fi

case "$1" in
    install)
        if [ -z "$2" ]; then
            echo "Usage: $0 install <package>"
            exit 1
        fi

        PACKAGE="$2"
        DOWNLOAD_FILE="$REPO/$PACKAGE/download"

        URL="$(curl -fsSL "$DOWNLOAD_FILE")" || {
            echo "Error: failed to retrieve the download URL."
            exit 1
        }

        echo "Downloading $PACKAGE..."
        curl -fL "$URL" -o "$TMP_DIR/$PACKAGE.apk" || {
            echo "Error: failed to download the APK."
            exit 1
        }

        echo "Installing $PACKAGE..."
        pm install "$TMP_DIR/$PACKAGE.apk"

        rm -f "$TMP_DIR/$PACKAGE.apk"
        ;;

    remove)
        if [ -z "$2" ]; then
            echo "Usage: $0 remove <package>"
            exit 1
        fi

        echo "Removing $2..."
        pm uninstall "$2"
        ;;

    *)
        echo "Usage: $0 {install|remove} <package>"
        exit 1
        ;;
esac
