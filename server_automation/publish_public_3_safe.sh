#!/usr/bin/env bash
set -u

BASE="/home/server/MEGALIST"
SRC_FILE="$BASE/sources_public_3.txt"
BACKUP_SRC="/tmp/sources_public_3.before_safe.$$"
DIMONOVICH_URL="https://raw.githubusercontent.com/Dimonovich/TV/Dimonovich/FREE/TV"
DIMONOVICH_LOCAL="$BASE/cache_dimonovich.m3u"
LOG="$BASE/public_3_safe_publish.log"

REMOTE_INDEX="https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/index.dat"
REMOTE_TVBOX="https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/tvbox.m3u"

MIN_PUBLIC_COUNT=10000
MIN_TVBOX_COUNT=700

echo "[SAFE_PUBLIC_3] START $(date '+%F %T')" | tee -a "$LOG"

cd "$BASE" || exit 1



echo "[SAFE_PUBLIC_3] checking Dimonovich before publish..." | tee -a "$LOG"

OK=0

for attempt in 1 2 3 4 5; do
  echo "[SAFE_PUBLIC_3] Dimonovich attempt $attempt/5 $(date '+%F %T')" | tee -a "$LOG"

  TMP="/tmp/dimonovich_safe_download.$$"

  if curl -4 -L \
    --connect-timeout 30 \
    --max-time 240 \
    --retry 2 \
    --retry-delay 5 \
    --retry-all-errors \
    -A "Mozilla/5.0 TVbox-safe-publisher" \
    -o "$TMP" \
    "$DIMONOVICH_URL"; then

    COUNT=$(grep -c '^#EXTINF' "$TMP" || true)

    if [ "$COUNT" -ge 1000 ]; then
      mv "$TMP" "$DIMONOVICH_LOCAL"
      echo "[SAFE_PUBLIC_3] Dimonovich OK count=$COUNT saved=$DIMONOVICH_LOCAL" | tee -a "$LOG"
      OK=1
      break
    else
      echo "[SAFE_PUBLIC_3] Dimonovich BAD small count=$COUNT" | tee -a "$LOG"
      rm -f "$TMP"
    fi
  else
    echo "[SAFE_PUBLIC_3] Dimonovich download failed attempt=$attempt" | tee -a "$LOG"
    rm -f "$TMP"
  fi

  if [ "$attempt" -lt 5 ]; then
    echo "[SAFE_PUBLIC_3] waiting 5 minutes before retry..." | tee -a "$LOG"
    sleep 300
  fi
done

if [ "$OK" != "1" ]; then
  echo "[SAFE_PUBLIC_3] ERROR: Dimonovich not downloaded after 5 attempts. Publish cancelled." | tee -a "$LOG"
  exit 1
fi

cp "$SRC_FILE" "$BACKUP_SRC"

python3 - <<'PY'
from pathlib import Path

p = Path("/home/server/MEGALIST/sources_public_3.txt")
text = p.read_text(encoding="utf-8")

url = "https://raw.githubusercontent.com/Dimonovich/TV/Dimonovich/FREE/TV"
local = "/home/server/MEGALIST/cache_dimonovich.m3u"

if url in text:
    text = text.replace(url, local)
elif local in text:
    pass
else:
    text = text.rstrip() + "\n" + local + "\n"

p.write_text(text, encoding="utf-8")
print("OK: Dimonovich source switched to fresh local downloaded file")
PY

echo "[SAFE_PUBLIC_3] sources for this publish:" | tee -a "$LOG"
cat "$SRC_FILE" | tee -a "$LOG"

echo "[SAFE_PUBLIC_3] running original publish script..." | tee -a "$LOG"

./publish_public_3_no_zabava.sh
ORIGINAL_STATUS=$?

echo "[SAFE_PUBLIC_3] Setanta Georgia reorder after original publish..." | tee -a "$LOG"

if [ "$ORIGINAL_STATUS" -eq 0 ]; then
  GITHUB_REPO="/home/server/GitHub/sys-cache-7c91"
  TVBOX_FILE="$GITHUB_REPO/data/tvbox.m3u"
  SETANTA_REORDER="$BASE/reorder_setanta_georgia_first.py"

  if [ -x "$SETANTA_REORDER" ] && [ -f "$TVBOX_FILE" ]; then
    BEFORE_HASH=$(sha256sum "$TVBOX_FILE" | awk '{print $1}')

    "$SETANTA_REORDER" "$TVBOX_FILE" | tee -a "$LOG"

    AFTER_HASH=$(sha256sum "$TVBOX_FILE" | awk '{print $1}')

    if [ "$BEFORE_HASH" != "$AFTER_HASH" ]; then
      echo "[SAFE_PUBLIC_3] Setanta order changed, committing..." | tee -a "$LOG"

      cd "$GITHUB_REPO" || exit 1
      git add data/tvbox.m3u
      git commit -m "Setanta Georgia streams first" || true
      git push origin main

      echo "[SAFE_PUBLIC_3] waiting RAW GitHub for Setanta Georgia order..." | tee -a "$LOG"

      for RAW_ATTEMPT in 1 2 3 4 5 6 7 8 9 10; do
        curl -L -s --max-time 30 "https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/tvbox.m3u?setanta_wait=$(date +%s)_$RAW_ATTEMPT" \
          -o /tmp/tvbox_raw_setanta_wait_after_safe.m3u

        FIRST_SETANTA_1=$(python3 - <<'PY2'
from pathlib import Path
lines = Path("/tmp/tvbox_raw_setanta_wait_after_safe.m3u").read_text(encoding="utf-8", errors="ignore").splitlines()
for i, line in enumerate(lines):
    if line.startswith("#EXTINF") and line.endswith(",Setanta Sports 1"):
        print(lines[i + 1] if i + 1 < len(lines) else "")
        break
PY2
)

        FIRST_SETANTA_2=$(python3 - <<'PY2'
from pathlib import Path
lines = Path("/tmp/tvbox_raw_setanta_wait_after_safe.m3u").read_text(encoding="utf-8", errors="ignore").splitlines()
for i, line in enumerate(lines):
    if line.startswith("#EXTINF") and line.endswith(",Setanta Sports 2"):
        print(lines[i + 1] if i + 1 < len(lines) else "")
        break
PY2
)

        echo "[SAFE_PUBLIC_3] RAW Setanta attempt $RAW_ATTEMPT/10" | tee -a "$LOG"
        echo "[SAFE_PUBLIC_3] RAW first Setanta 1: $FIRST_SETANTA_1" | tee -a "$LOG"
        echo "[SAFE_PUBLIC_3] RAW first Setanta 2: $FIRST_SETANTA_2" | tee -a "$LOG"

        if echo "$FIRST_SETANTA_1" | grep -q "georgia_play.php?id=setanta_georgia" \
           && echo "$FIRST_SETANTA_2" | grep -q "georgia_play.php?id=setanta_sports_plus_georgia"; then
          echo "[SAFE_PUBLIC_3] RAW Setanta Georgia order OK" | tee -a "$LOG"
          break
        fi

        if [ "$RAW_ATTEMPT" -lt 10 ]; then
          echo "[SAFE_PUBLIC_3] RAW Setanta not ready yet, waiting 30 seconds..." | tee -a "$LOG"
          sleep 30
        fi
      done

      cd "$BASE" || exit 1
    else
      echo "[SAFE_PUBLIC_3] Setanta order already OK, no commit needed" | tee -a "$LOG"
    fi
  else
    echo "[SAFE_PUBLIC_3] WARNING: Setanta reorder script or tvbox.m3u not found" | tee -a "$LOG"
  fi
else
  echo "[SAFE_PUBLIC_3] SKIP Setanta reorder because original publish failed rc=$ORIGINAL_STATUS" | tee -a "$LOG"
fi

cp "$BACKUP_SRC" "$SRC_FILE"
rm -f "$BACKUP_SRC"
echo "[SAFE_PUBLIC_3] sources restored" | tee -a "$LOG"

if [ "$ORIGINAL_STATUS" -ne 0 ]; then
  echo "[SAFE_PUBLIC_3] ERROR: original publish failed rc=$ORIGINAL_STATUS. Safe publish will NOT report OK." | tee -a "$LOG"
  echo "[SAFE_PUBLIC_3] Reason is usually remote Lime expiration / bad_under_2h / remote validation failure." | tee -a "$LOG"
  exit "$ORIGINAL_STATUS"
fi

echo "[SAFE_PUBLIC_3] checking remote result..." | tee -a "$LOG"

REMOTE_PUBLIC_COUNT=$(curl -L -s --max-time 60 "$REMOTE_INDEX" | grep -c '^#EXTINF' || true)
REMOTE_TVBOX_COUNT=$(curl -L -s --max-time 60 "$REMOTE_TVBOX" | grep -c '^#EXTINF' || true)

echo "[SAFE_PUBLIC_3] remote public count=$REMOTE_PUBLIC_COUNT" | tee -a "$LOG"
echo "[SAFE_PUBLIC_3] remote tvbox count=$REMOTE_TVBOX_COUNT" | tee -a "$LOG"

if [ "$REMOTE_PUBLIC_COUNT" -ge "$MIN_PUBLIC_COUNT" ] && [ "$REMOTE_TVBOX_COUNT" -ge "$MIN_TVBOX_COUNT" ]; then
  echo "[SAFE_PUBLIC_3] OK $(date '+%F %T')" | tee -a "$LOG"
  exit 0
fi

echo "[SAFE_PUBLIC_3] ERROR: remote checks failed. original_status=$ORIGINAL_STATUS" | tee -a "$LOG"
exit 1
