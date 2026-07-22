#!/bin/bash
set -e

LOG_PREFIX="[PUBLIC_3]"
MEGA="/home/server/MEGALIST"
REPO="/home/server/GitHub/sys-cache-7c91"
DATA="$REPO/data"

BAD_FILTER='zabava|zunotv\.workers\.dev|127\.0\.0\.1|localhost|ace/getstream|acestream|\.mp4|\.avi|\.mkv|\.mov|adult|18\+|porn|playboy|brazzers|redlight|эрот'

echo "$LOG_PREFIX START $(date '+%Y-%m-%d %H:%M:%S')"

cd "$MEGA"

echo "$LOG_PREFIX build public start"
"$MEGA/build_public_3_no_zabava.py"
echo "$LOG_PREFIX build public done"

echo "$LOG_PREFIX public local checks"

COUNT=$(grep -c "^#EXTINF" "$MEGA/public_3_no_zabava.m3u" || true)
echo "$LOG_PREFIX public local count=$COUNT"

BAD=$(grep -Ei "$BAD_FILTER" "$MEGA/public_3_no_zabava.m3u" | head -1 || true)

if [ -n "$BAD" ]; then
  echo "$LOG_PREFIX ERROR: public bad filter found:"
  echo "$BAD"
  exit 1
fi

if [ "$COUNT" -lt 5000 ]; then
  echo "$LOG_PREFIX ERROR: public too few streams: $COUNT"
  exit 1
fi

echo "$LOG_PREFIX build TVbox canonical start"
"$MEGA/build_tvbox_canonical.py"
echo "$LOG_PREFIX build TVbox canonical done"

TVBOX_COUNT=$(grep -c "^#EXTINF" "$MEGA/tvbox_canonical.m3u" || true)
echo "$LOG_PREFIX tvbox canonical count=$TVBOX_COUNT"

if [ "$TVBOX_COUNT" -lt 100 ]; then
  echo "$LOG_PREFIX ERROR: TVbox canonical too few streams: $TVBOX_COUNT"
  exit 1
fi

echo "$LOG_PREFIX real Lime availability filter start"
if [ -x "$MEGA/filter_tvbox_lime_real.py" ]; then
  "$MEGA/filter_tvbox_lime_real.py"

  REAL_LIME_COUNT=$(grep -c "^#EXTINF" "$MEGA/tvbox_canonical_lime_real_checked.m3u" || true)
  REAL_LIME_LEFT=$(grep -c "mhd128.iptv2022.com" "$MEGA/tvbox_canonical_lime_real_checked.m3u" || true)

  echo "$LOG_PREFIX real Lime filtered count=$REAL_LIME_COUNT"
  echo "$LOG_PREFIX real Lime left=$REAL_LIME_LEFT"

  if [ "$REAL_LIME_COUNT" -lt 700 ]; then
    echo "$LOG_PREFIX ERROR: TVbox after real Lime filter too few streams: $REAL_LIME_COUNT"
    exit 1
  fi

  cp "$MEGA/tvbox_canonical.m3u" "$MEGA/tvbox_canonical.before_lime_real_filter_$(date +%Y%m%d_%H%M%S).m3u"
  cp "$MEGA/tvbox_canonical_lime_real_checked.m3u" "$MEGA/tvbox_canonical.m3u"
else
  echo "$LOG_PREFIX ERROR: filter_tvbox_lime_real.py not found or not executable"
  exit 1
fi
echo "$LOG_PREFIX real Lime availability filter done"

echo "$LOG_PREFIX optimize TVbox Lime priority start"
"$MEGA/optimize_tvbox_canonical_lime.py"
echo "$LOG_PREFIX optimize TVbox Lime priority done"

OPT_COUNT=$(grep -c "^#EXTINF" "$MEGA/tvbox_canonical_optimized.m3u" || true)
OPT_LIME=$(grep -c "mhd128.iptv2022.com" "$MEGA/tvbox_canonical_optimized.m3u" || true)

echo "$LOG_PREFIX tvbox optimized count=$OPT_COUNT"
echo "$LOG_PREFIX tvbox optimized lime=$OPT_LIME"

if [ "$OPT_COUNT" -lt 100 ]; then
  echo "$LOG_PREFIX ERROR: optimized TVbox too few streams: $OPT_COUNT"
  exit 1
fi

echo "$LOG_PREFIX check optimized Lime expiration"

python3 - <<'PY'
from pathlib import Path
import re, datetime, sys

p = Path("/home/server/MEGALIST/tvbox_canonical_optimized.m3u")
text = p.read_text(encoding="utf-8", errors="ignore")

items = re.findall(r"#EXTINF.*?,(.+?)\n(https://mhd128\.iptv2022\.com/[^\n]+)", text)
now = datetime.datetime.now(datetime.UTC)

bad = []
hours = []

for title, url in items:
    m = re.search(r",(\d{10})/streaming/", url)
    if not m:
        bad.append((title, "NO_TIMESTAMP", url))
        continue

    exp = datetime.datetime.fromtimestamp(int(m.group(1)), datetime.UTC)
    left = round((exp - now).total_seconds() / 3600, 2)
    hours.append(left)

    if left < 2:
        bad.append((title, left, url))

print("lime streams:", len(items))
print("min_left:", min(hours) if hours else "-")
print("max_left:", max(hours) if hours else "-")
print("bad_under_2h:", len(bad))

if bad:
    for title, left, url in bad[:30]:
        print(title, left, url)
    sys.exit(2)
PY

echo "$LOG_PREFIX accept optimized TVbox canonical"
cp "$MEGA/tvbox_canonical.m3u" "$MEGA/tvbox_canonical.before_auto_optimize_$(date +%Y%m%d_%H%M%S).m3u"
cp "$MEGA/tvbox_canonical_optimized.m3u" "$MEGA/tvbox_canonical.m3u"

echo "$LOG_PREFIX placeholder filter start"
if [ -x "$MEGA/filter_tvbox_placeholders.py" ]; then
  "$MEGA/filter_tvbox_placeholders.py"

  PLACEHOLDER_COUNT=$(grep -c "^#EXTINF" "$MEGA/tvbox_canonical.no_placeholders.m3u" || true)
  PLACEHOLDER_LEFT=$(grep -ciE "stream8.cinerama.uz|stream1.cinerama.uz|cache1.cinerama.uz|168.119.58.242" "$MEGA/tvbox_canonical.no_placeholders.m3u" || true)

  echo "$LOG_PREFIX placeholder filtered count=$PLACEHOLDER_COUNT"
  echo "$LOG_PREFIX suspicious cinerama/168 left=$PLACEHOLDER_LEFT"

  if [ "$PLACEHOLDER_COUNT" -lt 700 ]; then
    echo "$LOG_PREFIX ERROR: TVbox after placeholder filter too few streams: $PLACEHOLDER_COUNT"
    exit 1
  fi

  cp "$MEGA/tvbox_canonical.m3u" "$MEGA/tvbox_canonical.before_placeholder_filter_$(date +%Y%m%d_%H%M%S).m3u"
  cp "$MEGA/tvbox_canonical.no_placeholders.m3u" "$MEGA/tvbox_canonical.m3u"
else
  echo "$LOG_PREFIX ERROR: filter_tvbox_placeholders.py not found or not executable"
  exit 1
fi
echo "$LOG_PREFIX placeholder filter done"

echo "$LOG_PREFIX copy to github repo"

cd "$REPO"

cp "$MEGA/public_3_no_zabava.m3u" "$DATA/index.dat"


# --- Romantica guard: если пересборка потеряла TV1000 Romantica, возвращаем её перед публикацией ---
if ! grep -qiE 'viju-tv1000-romantica|viju TV1000 Romantica|TV1000 Romantica|Romantika_HD' "$MEGA/tvbox_canonical.m3u"; then
  echo "--- Romantica guard: TV1000 Romantica missing, appending fixed block ---"
  echo "" >> "$MEGA/tvbox_canonical.m3u"
  cat "$MEGA/tvbox_romantica_block.m3u" >> "$MEGA/tvbox_canonical.m3u"
else
  echo "--- Romantica guard: TV1000 Romantica already present ---"
fi

cp "$MEGA/tvbox_canonical.m3u" "$DATA/tvbox.m3u"
cp "$MEGA/tvbox_canonical.m3u" "$DATA/tvbox_romantica.m3u"
# DISABLED 2026-07-09: do not overwrite app catalog.json from old MEGA catalog
# cp "$MEGA/tvbox_catalog.json" "$DATA/catalog.json"
cp "$MEGA/tvbox_canonical_report.tsv" "$DATA/tvbox_canonical_report.tsv"
cp "$MEGA/tvbox_canonical_summary.txt" "$DATA/tvbox_canonical_summary.txt"
cp "$MEGA/tvbox_canonical_lime_priority_report.tsv" "$DATA/tvbox_canonical_lime_priority_report.tsv"
cp "$MEGA/tvbox_canonical_lime_priority_summary.txt" "$DATA/tvbox_canonical_lime_priority_summary.txt"
cp "$MEGA/tvbox_placeholder_filter_report.tsv" "$DATA/tvbox_placeholder_filter_report.tsv" 2>/dev/null || true

echo "$LOG_PREFIX generate TVbox app config"

TVBOX_STREAMS=$(grep -c '^#EXTINF' "$DATA/tvbox.m3u" 2>/dev/null || echo 0)
PUBLIC_STREAMS=$(grep -c '^#EXTINF' "$DATA/index.dat" 2>/dev/null || echo 0)
LIME_STREAMS=$(grep -c 'mhd128.iptv2022.com' "$DATA/tvbox.m3u" 2>/dev/null || true)
LIME_STREAMS=$(echo "$LIME_STREAMS" | head -n 1)
LIME_STREAMS=${LIME_STREAMS:-0}
GENERATED_AT=$(date '+%Y-%m-%d %H:%M:%S %Z')
CATALOG_VERSION=$(date '+%Y%m%d_%H%M%S')
TVBOX_M3U_URL="https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/tvbox_auto_final_test.m3u?v=$CATALOG_VERSION"
CATALOG_JSON_URL="https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/catalog.json?v=$CATALOG_VERSION"

cat > "$DATA/app_config.json" <<EOF
{
  "app": "TVbox",
  "schema_version": 1,
  "generated_at": "$GENERATED_AT",
  "current_catalog": "stable",
  "min_app_version": "1.6.0",
  "latest_app_version": "1.7.0",
  "catalog": {
    "url": "$TVBOX_M3U_URL",
    "catalog_json_url": "$CATALOG_JSON_URL",
    "streams": $TVBOX_STREAMS,
    "lime_streams": $LIME_STREAMS,
    "cache_seconds": 300
  },
  "public_playlist": {
    "url": "https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/index.dat",
    "streams": $PUBLIC_STREAMS
  },
  "epg": {
    "url": "https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/tvbox_epg_romantica.xml.gz",
    "summary_url": "https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/tvbox_epg_summary.txt",
    "cache_hours": 12
  },
  "reports": {
    "status": "https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/tvbox_status.txt",
    "summary": "https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/tvbox_canonical_summary.txt",
    "lime_summary": "https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/tvbox_canonical_lime_priority_summary.txt"
  },
  "update": {
    "url": "https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/apk/TVbox_1.7.0.apk?v=$CATALOG_VERSION",
    "message": "Доступна новая версия TVbox 1.7.0. Обновите приложение до актуальной версии."
  }
}
EOF

# Делаем копию конфига под новым именем, чтобы обходить RAW-кэш GitHub
cp "$DATA/app_config.json" "$DATA/app_config_v2.json"
python3 -m json.tool "$DATA/app_config_v2.json" >/dev/null
echo "$LOG_PREFIX app_config_v2.json updated"


echo "$LOG_PREFIX generate TVbox status"

cat > "$DATA/tvbox_status.txt" <<EOF
TVbox Server Status
Generated at: $(date '+%Y-%m-%d %H:%M:%S %Z')

Catalog:
- URL: https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/tvbox_romantica.m3u
- Streams: $(grep -c '^#EXTINF' "$DATA/tvbox.m3u" 2>/dev/null || echo 0)

Public playlist:
- URL: https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/index.dat
- Streams: $(grep -c '^#EXTINF' "$DATA/index.dat" 2>/dev/null || echo 0)

EPG:
- URL: https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/tvbox_epg_romantica.xml.gz
- Summary: https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/tvbox_epg_summary.txt

Reports:
- Canonical summary: https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/tvbox_canonical_summary.txt
- Lime summary: https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/tvbox_canonical_lime_priority_summary.txt

App config:
- URL: https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/app_config.json
- URL v2: https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/app_config_v2.json
EOF

git add \
  data/index.dat \
  data/tvbox.m3u \
  data/tvbox_romantica.m3u \
  data/catalog.json \
  data/tvbox_canonical_report.tsv \
  data/tvbox_canonical_summary.txt \
  data/tvbox_canonical_lime_priority_report.tsv \
  data/tvbox_canonical_lime_priority_summary.txt \
  data/tvbox_placeholder_filter_report.tsv \
  data/tvbox_status.txt \
  data/app_config.json \
  data/app_config_v2.json

if git diff --cached --quiet; then
  echo "$LOG_PREFIX no changes to commit"
else
  git commit -m "Update data"
  git push
  echo "$LOG_PREFIX pushed to github"
fi

echo "$LOG_PREFIX remote public check"

REMOTE_COUNT=$(curl -L -s --max-time 30 https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/index.dat | grep -c "^#EXTINF" || true)
echo "$LOG_PREFIX remote public count=$REMOTE_COUNT"

if [ "$REMOTE_COUNT" -lt 5000 ]; then
  echo "$LOG_PREFIX ERROR: remote public count too low: $REMOTE_COUNT"
  exit 1
fi

REMOTE_BAD=$(curl -L -s --max-time 30 https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/index.dat \
  | grep -Ei "$BAD_FILTER" \
  | head -1 || true)

if [ -n "$REMOTE_BAD" ]; then
  echo "$LOG_PREFIX ERROR: remote public bad filter found:"
  echo "$REMOTE_BAD"
  exit 1
fi

echo "$LOG_PREFIX remote TVbox check"

REMOTE_TVBOX_OK=0
REMOTE_TVBOX_LAST_RC=1

for REMOTE_ATTEMPT in 1 2 3 4 5 6 7 8 9 10; do
  echo "$LOG_PREFIX remote TVbox check attempt $REMOTE_ATTEMPT/10"

  curl -L -s --max-time 30 "https://raw.githubusercontent.com/Commodo163/sys-cache-7c91/main/data/tvbox_romantica.m3u?remote_tvbox_check=$(date +%s)_$REMOTE_ATTEMPT" \
    -o /tmp/tvbox_remote_auto_check.m3u

  REMOTE_TVBOX_COUNT=$(grep -c "^#EXTINF" /tmp/tvbox_remote_auto_check.m3u || true)
  REMOTE_TVBOX_LIME=$(grep -c "mhd128.iptv2022.com" /tmp/tvbox_remote_auto_check.m3u || true)

  echo "$LOG_PREFIX remote tvbox count=$REMOTE_TVBOX_COUNT"
  echo "$LOG_PREFIX remote tvbox lime=$REMOTE_TVBOX_LIME"

  if [ "$REMOTE_TVBOX_COUNT" -lt 100 ]; then
    echo "$LOG_PREFIX WARNING: remote TVbox count too low: $REMOTE_TVBOX_COUNT"
    REMOTE_TVBOX_LAST_RC=1
  else
    python3 - <<'PY2'
from pathlib import Path
import re, datetime, sys

p = Path("/tmp/tvbox_remote_auto_check.m3u")
text = p.read_text(encoding="utf-8", errors="ignore")

items = re.findall(r"#EXTINF.*?,(.+?)\n(https://mhd128\.iptv2022\.com/[^\n]+)", text)
now = datetime.datetime.now(datetime.UTC)

bad = []
hours = []

for title, url in items:
    m = re.search(r",(\d{10})/streaming/", url)
    if not m:
        bad.append((title, "NO_TIMESTAMP", url))
        continue

    exp = datetime.datetime.fromtimestamp(int(m.group(1)), datetime.UTC)
    left = round((exp - now).total_seconds() / 3600, 2)
    hours.append(left)

    if left < 2:
        bad.append((title, left, url))

print("remote lime streams:", len(items))
print("remote min_left:", min(hours) if hours else "-")
print("remote max_left:", max(hours) if hours else "-")
print("remote bad_under_2h:", len(bad))

if bad:
    for title, left, url in bad[:30]:
        print(title, left, url)
    sys.exit(2)
PY2

    REMOTE_TVBOX_LAST_RC=$?

    if [ "$REMOTE_TVBOX_LAST_RC" -eq 0 ]; then
      REMOTE_TVBOX_OK=1
      echo "$LOG_PREFIX remote TVbox check OK on attempt $REMOTE_ATTEMPT/10"
      break
    fi
  fi

  if [ "$REMOTE_ATTEMPT" -lt 10 ]; then
    echo "$LOG_PREFIX remote TVbox not ready yet, waiting 30 seconds..."
    sleep 30
  fi
done

if [ "$REMOTE_TVBOX_OK" != "1" ]; then
  echo "$LOG_PREFIX ERROR: remote TVbox check failed after 10 attempts rc=$REMOTE_TVBOX_LAST_RC"
  exit "$REMOTE_TVBOX_LAST_RC"
fi

echo "$LOG_PREFIX OK $(date '+%Y-%m-%d %H:%M:%S')"
