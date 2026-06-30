#!/bin/bash
set -u

DIR="/home/server/TVBOX_EPG"
REPO="/home/server/GitHub/sys-cache-7c91"
DATA="$REPO/data"

LOG="$DIR/tvbox_epg_update.log"
ERR="$DIR/tvbox_epg_update_error.log"

SOURCE_URL="http://epg.one/epg2.xml.gz"
IPTVX_URL="https://iptvx.one/EPG.xml.gz"

MIN_CHANNELS=60
MIN_PROGRAMMES=15000
MAX_SIZE_MB=15

cd "$DIR" || exit 1

{
  echo
  echo "=== TVBOX EPG SAFE UPDATE START $(date '+%Y-%m-%d %H:%M:%S') ==="

  echo "--- backup current good files ---"
  mkdir -p "$DIR/backups"

  TS="$(date '+%Y%m%d_%H%M%S')"

  [ -f tvbox_epg.xml.gz ] && cp tvbox_epg.xml.gz "backups/tvbox_epg.xml.gz.$TS"
  [ -f tvbox_epg.xml ] && cp tvbox_epg.xml "backups/tvbox_epg.xml.$TS"
  [ -f tvbox_epg_report.tsv ] && cp tvbox_epg_report.tsv "backups/tvbox_epg_report.tsv.$TS"
  [ -f tvbox_epg_summary.txt ] && cp tvbox_epg_summary.txt "backups/tvbox_epg_summary.txt.$TS"
  [ -f epg2.xml.gz ] && cp epg2.xml.gz "backups/epg2.xml.gz.$TS"

  echo "--- download fresh epg.one ---"
  curl -L --fail --max-time 240 -o epg2.xml.gz.new "$SOURCE_URL"
  CURL_CODE=$?

  if [ "$CURL_CODE" -ne 0 ]; then
    echo "BAD UPDATE: curl failed code=$CURL_CODE"
    rm -f epg2.xml.gz.new
    echo "=== TVBOX EPG SAFE UPDATE END BAD $(date '+%Y-%m-%d %H:%M:%S') ==="
    exit 1
  fi

  echo "--- gzip test source ---"
  gzip -t epg2.xml.gz.new
  GZIP_SOURCE=$?

  if [ "$GZIP_SOURCE" -ne 0 ]; then
    echo "BAD UPDATE: downloaded epg2.xml.gz.new is not valid gzip"
    rm -f epg2.xml.gz.new
    echo "=== TVBOX EPG SAFE UPDATE END BAD $(date '+%Y-%m-%d %H:%M:%S') ==="
    exit 1
  fi

  mv epg2.xml.gz.new epg2.xml.gz

  echo "--- download fresh iptvx epg ---"
  curl -L --fail --max-time 240 -o iptvx_epg.xml.gz.new "$IPTVX_URL"
  CURL_IPTVX_CODE=$?

  if [ "$CURL_IPTVX_CODE" -ne 0 ]; then
    echo "BAD UPDATE: iptvx curl failed code=$CURL_IPTVX_CODE"
    rm -f iptvx_epg.xml.gz.new
    echo "=== TVBOX EPG SAFE UPDATE END BAD $(date '+%Y-%m-%d %H:%M:%S') ==="
    exit 1
  fi

  echo "--- gzip test iptvx source ---"
  gzip -t iptvx_epg.xml.gz.new
  GZIP_IPTVX=$?

  if [ "$GZIP_IPTVX" -ne 0 ]; then
    echo "BAD UPDATE: downloaded iptvx_epg.xml.gz.new is not valid gzip"
    rm -f iptvx_epg.xml.gz.new
    echo "=== TVBOX EPG SAFE UPDATE END BAD $(date '+%Y-%m-%d %H:%M:%S') ==="
    exit 1
  fi

  mv iptvx_epg.xml.gz.new iptvx_epg.xml.gz

  echo "--- build filtered TVbox EPG ---"
  ./build_tvbox_epg.py
  BUILD_CODE=$?

  if [ "$BUILD_CODE" -ne 0 ]; then
    echo "BAD UPDATE: build_tvbox_epg.py failed code=$BUILD_CODE"
    echo "=== TVBOX EPG SAFE UPDATE END BAD $(date '+%Y-%m-%d %H:%M:%S') ==="
    exit 1
  fi

  echo "--- validate output gzip ---"
  gzip -t tvbox_epg.xml.gz
  GZIP_OUT=$?

  if [ "$GZIP_OUT" -ne 0 ]; then
    echo "BAD UPDATE: tvbox_epg.xml.gz is not valid gzip"
    echo "=== TVBOX EPG SAFE UPDATE END BAD $(date '+%Y-%m-%d %H:%M:%S') ==="
    exit 1
  fi

  CHANNELS=$(gzip -cd tvbox_epg.xml.gz | grep -c "<channel ")
  PROGRAMMES=$(gzip -cd tvbox_epg.xml.gz | grep -c "<programme ")
  SIZE_MB=$(du -m tvbox_epg.xml.gz | awk '{print $1}')

  echo "channels=$CHANNELS"
  echo "programmes=$PROGRAMMES"
  echo "size_mb=$SIZE_MB"

  if [ "$CHANNELS" -lt "$MIN_CHANNELS" ]; then
    echo "BAD UPDATE: too few channels: $CHANNELS"
    echo "=== TVBOX EPG SAFE UPDATE END BAD $(date '+%Y-%m-%d %H:%M:%S') ==="
    exit 1
  fi

  if [ "$PROGRAMMES" -lt "$MIN_PROGRAMMES" ]; then
    echo "BAD UPDATE: too few programmes: $PROGRAMMES"
    echo "=== TVBOX EPG SAFE UPDATE END BAD $(date '+%Y-%m-%d %H:%M:%S') ==="
    exit 1
  fi

  if [ "$SIZE_MB" -gt "$MAX_SIZE_MB" ]; then
    echo "BAD UPDATE: file too large: ${SIZE_MB}MB"
    echo "=== TVBOX EPG SAFE UPDATE END BAD $(date '+%Y-%m-%d %H:%M:%S') ==="
    exit 1
  fi

  echo "--- publish to GitHub repo ---"
  cp tvbox_epg.xml.gz "$DATA/tvbox_epg.xml.gz"
  cp tvbox_epg.xml.gz "$DATA/tvbox_epg_romantica.xml.gz"
  cp tvbox_epg_report.tsv "$DATA/tvbox_epg_report.tsv"
  cp tvbox_epg_summary.txt "$DATA/tvbox_epg_summary.txt"

  cd "$REPO" || exit 1

  git add data/tvbox_epg.xml.gz data/tvbox_epg_romantica.xml.gz data/tvbox_epg_report.tsv data/tvbox_epg_summary.txt

  if git diff --cached --quiet; then
    echo "No GitHub changes. Nothing to commit."
  else
    git commit -m "Update TVbox EPG"
    git push
  fi

  echo "--- remote verify ---"
  curl -L -s --max-time 60 https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/tvbox_epg_romantica.xml.gz -o /tmp/tvbox_epg_remote_auto_check.xml.gz

  gzip -t /tmp/tvbox_epg_remote_auto_check.xml.gz
  REMOTE_GZIP=$?

  REMOTE_CHANNELS=$(gzip -cd /tmp/tvbox_epg_remote_auto_check.xml.gz | grep -c "<channel ")
  REMOTE_PROGRAMMES=$(gzip -cd /tmp/tvbox_epg_remote_auto_check.xml.gz | grep -c "<programme ")

  echo "remote_gzip=$REMOTE_GZIP"
  echo "remote_channels=$REMOTE_CHANNELS"
  echo "remote_programmes=$REMOTE_PROGRAMMES"

  if [ "$REMOTE_GZIP" -ne 0 ] || [ "$REMOTE_CHANNELS" -lt "$MIN_CHANNELS" ] || [ "$REMOTE_PROGRAMMES" -lt "$MIN_PROGRAMMES" ]; then
    echo "BAD UPDATE: remote verification failed"
    echo "=== TVBOX EPG SAFE UPDATE END BAD $(date '+%Y-%m-%d %H:%M:%S') ==="
    exit 1
  fi

  echo "GOOD UPDATE: TVbox EPG updated and published"
  echo "=== TVBOX EPG SAFE UPDATE END OK $(date '+%Y-%m-%d %H:%M:%S') ==="

} >> "$LOG" 2>> "$ERR"
