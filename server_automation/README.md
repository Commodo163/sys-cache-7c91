# TVbox server automation snapshot

Этот каталог содержит рабочие серверные файлы автообновления TVbox.

## Основная схема

- `/home/server/MEGALIST/publish_public_3_safe.sh`
  - безопасный запуск публикации
  - обновляет публичный плейлист
  - пересобирает TVbox playlist
  - публикует данные в GitHub

- `/home/server/MEGALIST/publish_public_3_no_zabava.sh`
  - основной скрипт публикации
  - публикует `data/tvbox.m3u`
  - публикует `data/tvbox_romantica.m3u`
  - публикует `data/catalog.json`
  - публикует `data/app_config.json`
  - содержит Romantica guard

- `/home/server/MEGALIST/check_tvbox_autoupdate_health.sh`
  - проверяет, что приложение получает правильный playlist/config/EPG
  - проверяет TV1000 Romantica
  - проверяет tvg-id
  - проверяет логотип
  - проверяет EPG

- `/home/server/TVBOX_EPG/update_tvbox_epg_safe.sh`
  - обновляет EPG
  - публикует `tvbox_epg_romantica.xml.gz`

## Важное

TV1000 Romantica должна быть в:
- `tvbox_canonical_channels.tsv`
- `tvbox_logo_map.tsv`
- `tvbox_epg_map.tsv`
- `tvbox_romantica.m3u`
- `catalog.json`
- `tvbox_epg_romantica.xml.gz`

