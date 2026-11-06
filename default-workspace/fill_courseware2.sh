#!/bin/bash
# Fill courseware pages with one exported image per page, using validated navigation.
# Navigation: read "页数 N/M" from AX, paste image N, Esc, Down-arrow to next page.
set -u
DIR="/Users/tal/Desktop/科学/26年/秋/科学长期班/L5-第4讲-机器人记忆力出色的原因是什么？/PPT导出"
AX="/Users/tal/Documents/deepseek-harness/default-workspace/tools/axctl"
START=${1:-20}
END=${2:-91}

page_now() { "$AX" tree "XESlideEditor" 12 2>/dev/null | grep -o '页数 [0-9]\+/' | grep -o '[0-9]\+'; }

win_center() {
  "$AX" windows "XESlideEditor" 2>/dev/null | head -1 | sed -E 's/.*x=([0-9-]+) y=([0-9-]+) w=([0-9]+) h=([0-9]+).*/\1 \2 \3 \4/' |
    awk '{printf "%d %d\n", $1 + $3*0.45, $2 + $4*0.55}'
}

for N in $(seq "$START" "$END"); do
  cur=$(page_now)
  if [ "${cur:-0}" != "$N" ]; then
    echo "MISMATCH expected=$N got=${cur:-none} -- stopping"
    break
  fi
  read -r CX CY <<< "$(win_center)"
  osascript -e "set the clipboard to (read (POSIX file \"$DIR/$N.png\") as «class PNGf»)" 2>/dev/null
  "$AX" click "$CX" "$CY" >/dev/null
  sleep 0.25
  "$AX" hotkey 9 cmd >/dev/null
  sleep 1.55
  "$AX" key 53 >/dev/null
  sleep 0.3
  "$AX" key 125 >/dev/null
  sleep 0.95
  echo "page $N filled"
  if [ $((N % 10)) -eq 0 ]; then
    screencapture -x "/tmp/full_$N.png"
  fi
done

echo "LOOP END at page $(page_now)"
screencapture -x /tmp/full_end.png
