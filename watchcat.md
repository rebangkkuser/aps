# aps WatchCat (meow? meow.)
## What is the WatchCat?
WatchCat is a file on the aps repository which stores bugs, the bug lines, and who discovered the bug.
See /watchcat.txt for no Markdown renderizing (better for less)

### bug #1 — empty invocation produces a shift error 
lines mentioned: **543** on **/aps.sh**.

by: ***@bangkkuser***

lines mentioned on this relact

***/aps.sh***, **543**
```sh
shift
```
### bug #2 — flags not working when placed BEFORE the command.

by: **bangkkuser**

lines mentioned on this relact

***/aps.sh***, **533 - 540 (8)**
```sh
while [ "$#" -gt 0 ]; do
    case "$1" in
        -y) AUTO_YES=1 ;;
        --dhash) DHASH=1 ;;
        *) break ;;
    esac
    shift
done
```
