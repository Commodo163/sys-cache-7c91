#!/usr/bin/env bash
set -u

LOG="/home/server/MEGALIST/tvbox_autoupdate_health.log"
TMP_M3U="/tmp/tvbox_romantica_health_check.m3u"
TMP_CONFIG="/tmp/app_config_health_check.json"
TMP_EPG="/tmp/tvbox_epg_romantica_health_check.xml.gz"

APP_CONFIG_URL="https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/app_config.json?health_check=$(date +%s)"
M3U_URL="https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/tvbox_romantica.m3u?health_check=$(date +%s)"
EPG_URL="https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/tvbox_epg_romantica.xml.gz?health_check=$(date +%s)"

echo "=== TVBOX AUTOUPDATE HEALTH START $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOG"

FAIL=0

echo "--- download app_config ---" >> "$LOG"
curl -L -s --max-time 60 "$APP_CONFIG_URL" -o "$TMP_CONFIG"

if grep -q "tvbox_romantica.m3u" "$TMP_CONFIG"; then
  echo "OK app_config uses tvbox_romantica.m3u" >> "$LOG"
else
  echo "FAIL app_config does not use tvbox_romantica.m3u" >> "$LOG"
  FAIL=1
fi

echo "--- download playlist ---" >> "$LOG"
curl -L -s --max-time 60 "$M3U_URL" -o "$TMP_M3U"

COUNT=$(grep -c '^#EXTINF' "$TMP_M3U" 2>/dev/null || echo 0)
echo "playlist_streams=$COUNT" >> "$LOG"

if grep -qi "viju TV1000 Romantica" "$TMP_M3U"; then
  echo "OK Romantica title found" >> "$LOG"
else
  echo "FAIL Romantica title not found" >> "$LOG"
  FAIL=1
fi

if grep -q 'tvg-id="viju-tv1000-romantica"' "$TMP_M3U"; then
  echo "OK Romantica tvg-id found" >> "$LOG"
else
  echo "FAIL Romantica tvg-id missing" >> "$LOG"
  FAIL=1
fi

if grep -q 'viju-tv1000-romantica.png' "$TMP_M3U"; then
  echo "OK Romantica logo found" >> "$LOG"
else
  echo "FAIL Romantica logo missing" >> "$LOG"
  FAIL=1
fi

echo "--- download EPG ---" >> "$LOG"
curl -L -s --max-time 60 "$EPG_URL" -o "$TMP_EPG"

if gzip -t "$TMP_EPG" 2>/dev/null; then
  echo "OK EPG gzip" >> "$LOG"
else
  echo "FAIL EPG gzip broken" >> "$LOG"
  FAIL=1
fi

EPG_COUNT=$(zgrep -c 'channel="viju-tv1000-romantica"' "$TMP_EPG" 2>/dev/null || echo 0)
echo "romantica_epg_programmes=$EPG_COUNT" >> "$LOG"

if [ "$EPG_COUNT" -gt 0 ]; then
  echo "OK Romantica EPG programmes found" >> "$LOG"
else
  echo "FAIL Romantica EPG programmes missing" >> "$LOG"
  FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
  echo "GOOD HEALTH: TVbox autoupdate OK" >> "$LOG"
  echo "=== TVBOX AUTOUPDATE HEALTH END OK $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOG"
  echo "OK $(date '+%Y-%m-%d %H:%M:%S') streams=$COUNT romantica_epg=$EPG_COUNT"
  exit 0
else
  echo "BAD HEALTH: TVbox autoupdate has problems" >> "$LOG"
  echo "=== TVBOX AUTOUPDATE HEALTH END FAIL $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOG"
  echo "FAIL $(date '+%Y-%m-%d %H:%M:%S') streams=$COUNT romantica_epg=$EPG_COUNT"
  exit 1
fi
