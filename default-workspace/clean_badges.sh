#!/bin/bash
# Remove the stray "999341" 1-cell table on each page (only if the selection really is a table).
# Never presses Delete unless the properties panel shows table controls.
set -u
AX="/Users/tal/Documents/deepseek-harness/default-workspace/tools/axctl"
START=${1:-90}
END=${2:-17}

page_now() { "$AX" tree "XESlideEditor" 3 2>/dev/null | grep -o '页数 [0-9]\+/' | grep -o '[0-9]\+' | head -1; }
labels()  { "$AX" tree "XESlideEditor" 20 2>/dev/null | grep "AXStaticText" | sed 's/.*| //'; }

del=0; skip=0
for N in $(seq "$START" -1 "$END"); do
  cur=$(page_now)
  if [ "${cur:-0}" != "$N" ]; then echo "MISMATCH expected=$N got=${cur:-none} -- stopping"; break; fi

  "$AX" click 971 413 >/dev/null      # badge hotspot (canvas top-left)
  sleep 0.95
  L=$(labels)
  if echo "$L" | grep -q "上方插行"; then
    "$AX" key 51 >/dev/null           # Delete
    sleep 0.85
    del=$((del+1)); echo "page $N: table deleted"
  else
    "$AX" key 53 >/dev/null           # Esc: do NOT delete anything else
    sleep 0.3
    skip=$((skip+1)); echo "page $N: no table (kept) [$(echo "$L" | grep -E '图片样式|页面属性|文本属性' | head -1)]"
  fi

  "$AX" clicktext "XESlideEditor" "$N" >/dev/null 2>&1
  sleep 0.85
  "$AX" key 126 >/dev/null            # previous page
  sleep 0.75
  if [ $((N % 10)) -eq 0 ]; then screencapture -R 600,150,1280,748 "/tmp/del_$N.png"; fi
done
echo "CLEAN DONE deleted=$del skipped=$skip now=$(page_now)"
screencapture -R 600,150,1280,748 /tmp/del_final.png
