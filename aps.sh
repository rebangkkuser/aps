#!/system/bin/sh

dir=/data/local/aps
rdir=$dir/repos
repos='https://github.com/rebangkkuser/aps/tree/main/main/pkg'
if [ ! $(cat $rdir/main.alist) = "$repos" ]; then
  echo "$repos" > $rdir/main.alist
fi

case "$1" in
  install)
   curl $(cat $rdir/main.alist)/$2/download) -o /tmp/aps/$2.apk
   pm install /tmp/aps/$2.apk
   rm -rf /tmp/aps/*
    ;;
  remove)
   pm uninstall "$2"
    ;;
esac
