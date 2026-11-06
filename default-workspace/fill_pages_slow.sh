#!/bin/bash
# Slow, verified fill: for each page N, click its thumbnail label (AX), verify 页数==N,
# then paste image N into the canvas. Aborts on any mismatch.
set -u
DIR="/Users/tal/Desktop/科学/26年/秋/科学长期班/L5-第4讲-机器人记忆力出色的原因是什么？/PPT导出"
AX="/Users/tal/Documents/deepseek-harness/default-workspace/tools/axctl"
START=${1:-21}
END=${2:-91}

page_now() { "$AX" tree "XESlideEditor" 3 2>/dev/null | grep -o '页数 [0-9]\+/' | grep -o '[0-9]\+' | head -1; }
win_geom() { "$AX" windows "XESlideEditor" 2>/dev/null | head -1 | sed -E 's/.*x=([0-9-]+) y=([0-9-]+) w=([0-9]+) h=([0-9]+).*/\1 \2 \3 \4/'; }

for N in $(seq "$START" "$END"); do
  read -r WX WY WW WH <<< "$(win_geom)"
  RAILX=$(( WX + 70 )); RAILY=$(( WY + 400 ))
  CX=$(( WX + WW * 55 / 100 )); CY=$(( WY + WH * 55 / 100 ))

  ok=0
  for try in 1 2 3 4; do
    out=$("$AX" clicktext "XESlideEditor" "$N" 2>&1)
    if echo "$out" | grep -q "no match"; then
      "$AX" scroll "$RAILX" "$RAILY" -400 >/dev/null 2>&1
      sleep 0.7
      continue
    fi
    sleep 1.3
    cur=$(page_now)
    if [ "${cur:-0}" = "$N" ]; then ok=1; break; fi
  done
  if [ "$ok" != "1" ]; then echo "ABORT: could not select page $N (now=$(page_now))"; break; fi

  osascript -e "set the clipboard to (read (POSIX file \"$DIR/$N.png\") as «class PNGf»)" 2>/dev/null
  "$AX" click "$CX" "$CY" >/dev/null
  sleep 0.3
  "$AX" hotkey 9 cmd >/dev/null
  sleep 1.7
  "$AX" key 53 >/dev/null
  sleep 0.35
  echo "page $N ok"
  if [ $((N % 10)) -eq 0 ]; then screencapture -x "/tmp/fill_$N.png"; fi
done
echo "DONE range $START-$END, now at page $(page_now)"
screencapture -x /tmp/fill_final.png
