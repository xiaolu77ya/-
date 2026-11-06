#!/bin/bash
# Fill pages: navigate with Down arrow (rail keeps focus), paste image N, Esc, Down.
# Aborts immediately if the page number doesn't match.
set -u
DIR="/Users/tal/Desktop/科学/26年/秋/科学长期班/L5-第4讲-机器人记忆力出色的原因是什么？/PPT导出"
AX="/Users/tal/Documents/deepseek-harness/default-workspace/tools/axctl"
START=${1:-21}
END=${2:-91}

page_now() { "$AX" tree "XESlideEditor" 3 2>/dev/null | grep -o '页数 [0-9]\+/' | grep -o '[0-9]\+' | head -1; }

for N in $(seq "$START" "$END"); do
  cur=$(page_now)
  if [ "${cur:-0}" != "$N" ]; then
    echo "MISMATCH expected=$N got=${cur:-none} -- stopping"
    break
  fi
  osascript -e "set the clipboard to (read (POSIX file \"$DIR/$N.png\") as «class PNGf»)" 2>/dev/null
  "$AX" hotkey 9 cmd >/dev/null
  sleep 2.0
  "$AX" key 53 >/dev/null      # deselect
  sleep 0.3
  "$AX" key 125 >/dev/null     # next page
  sleep 0.85
  echo "page $N ok"
  if [ $((N % 10)) -eq 0 ]; then screencapture -x "/tmp/fill_$N.png"; fi
done
echo "END at page $(page_now)"
screencapture -x /tmp/fill_final.png
