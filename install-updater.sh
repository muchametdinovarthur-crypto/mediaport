#!/usr/bin/env bash
# Один раз ставит автообновление МЕДИАПОРТ-брони: раз в 5 минут проверяет GitHub и обновляет код.
# Брони и настройки (папка data) при обновлении НЕ трогаются.
set -e
APP="${APP:-/root/mediaport-booking}"
REPO="${REPO:-https://raw.githubusercontent.com/muchametdinovarthur-crypto/mediaport/main}"
cat > /usr/local/bin/mp-update <<'UPD'
#!/usr/bin/env bash
APP="__APP__"; R="__REPO__"
NEW="$(curl -fsS --max-time 20 "$R/VERSION" 2>/dev/null | tr -d '[:space:]')" || exit 0
[ -n "$NEW" ] || exit 0
OLD="$(cat "$APP/.version" 2>/dev/null | tr -d '[:space:]')"
[ "$NEW" = "$OLD" ] && exit 0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
curl -fsS --max-time 120 -o "$T/app.tgz" "$R/app.tar.gz" || exit 0
mkdir "$T/new" && tar -xzf "$T/app.tgz" -C "$T/new" || exit 0
SRC="$T/new/mediaport-booking"
[ -f "$SRC/server/index.js" ] || exit 0
node --check "$SRC/server/index.js" 2>/dev/null || { echo "mp-update: новая версия не прошла проверку, пропускаю" >&2; exit 0; }
tar -czf "/root/mp-prev.tgz" -C "$APP" --exclude=data . 2>/dev/null || true
rm -rf "$SRC/data"
cp -a "$SRC/." "$APP/"
echo "$NEW" > "$APP/.version"
systemctl restart mediaport
sleep 3
if ! curl -fsS --max-time 10 localhost/healthz >/dev/null 2>&1; then
  echo "mp-update: сервис не поднялся, откатываю" >&2
  tar -xzf /root/mp-prev.tgz -C "$APP" && systemctl restart mediaport
  echo "$OLD" > "$APP/.version"
fi
UPD
sed -i "s#__APP__#$APP#; s#__REPO__#$REPO#" /usr/local/bin/mp-update
chmod +x /usr/local/bin/mp-update
cat > /etc/systemd/system/mp-update.service <<UNIT
[Unit]
Description=MEDIAPORT auto update
[Service]
Type=oneshot
ExecStart=/usr/local/bin/mp-update
UNIT
cat > /etc/systemd/system/mp-update.timer <<UNIT
[Unit]
Description=MEDIAPORT auto update every 5 min
[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now mp-update.timer >/dev/null 2>&1
/usr/local/bin/mp-update || true
echo "Автообновление включено. Версия: $(cat "$APP/.version" 2>/dev/null)"
