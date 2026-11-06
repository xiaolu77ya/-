#!/bin/bash
# Paste image N onto courseware page N, for N in [start..end]
set -u
DIR="/Users/tal/Desktop/科学/26年/秋/科学长期班/L5-第4讲-机器人记忆力出色的原因是什么？/PPT导出"
AX="/Users/tal/Documents/deepseek-harness/default-workspace/tools/axctl"
START=${1:-19}
END=${2:-91}

for N in $(seq "$START" "$END"); do
  "$AX" click 979 988        # page number box
  sleep 0.25
  "$AX" type "$N"
  sleep 0.15
  "$AX" key 36               # Enter -> jump
  sleep 1.0
  osascript -e "set the clipboard to (read (POSIX file \"$DIR/$N.png\") as «class PNGf»)" 2>/dev/null
  sleep 0.25
  "$AX" click 1360 625       # canvas center
  sleep 0.25
  "$AX" hotkey 9 cmd         # Cmd+V
  sleep 1.6
  echo "page $N done"
  if [ $((N % 10)) -eq 0 ]; then
    screencapture -R 950,281,1280,748 "/tmp/prog_$N.png"
  fi
done
screencapture -R 950,281,1280,748 "/tmp/prog_final.png"
echo "ALL DONE $START..$END"
