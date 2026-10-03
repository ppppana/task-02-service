#!/usr/bin/env bash
# Проверка стенда задания 02. Запускать на VPS:
#   bash check.sh [URL]
# URL по умолчанию: https://app.yohan-stock.duckdns.org
# Переменная STATE_DIR (необязательно): каталог состояния, по умолчанию /opt/task-02/state
# Код возврата: 0 — все проверки пройдены, 1 — есть ошибки.
set -uo pipefail

URL="${1:-https://app.yohan-stock.duckdns.org}"
STATE_DIR="${STATE_DIR:-/opt/task-02/state}"
FAIL=0

ok()   { echo "  [ OK ] $*"; }
bad()  { echo "  [FAIL] $*"; FAIL=1; }
code() { curl -s -o /dev/null -w '%{http_code}' "$1"; }

echo "Проверка задания 02: ${URL}"
echo "Время: $(date '+%F %T %Z')"
echo

echo "1. Контейнер и образ"
docker ps --filter name=task02-app --format '  {{.Names}}  {{.Status}}'
CURRENT="$(cat "${STATE_DIR}/current-image" 2>/dev/null || true)"
PREVIOUS="$(cat "${STATE_DIR}/previous-image" 2>/dev/null || true)"
RUNNING="$(docker inspect --format '{{.Config.Image}}' task02-app 2>/dev/null || true)"
REVISION="$(docker inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' task02-app 2>/dev/null || true)"
echo "  работает:       ${RUNNING:-нет}"
echo "  current-image:  ${CURRENT:-нет}"
echo "  previous-image: ${PREVIOUS:-нет}"
echo "  commit образа:  ${REVISION:-нет}"
if [ -n "${CURRENT}" ] && [ "${RUNNING}" = "${CURRENT}" ]; then
  ok "Работает сохранённый выпуск (digest совпадает)"
else
  bad "Работающий образ не совпадает с current-image"
fi
if [ -n "${PREVIOUS}" ]; then ok "Точка отката сохранена"; else bad "Нет previous-image"; fi
if [ -z "$(docker port task02-app 2>/dev/null)" ]; then
  ok "Порты приложения наружу не публикуются"
else
  bad "У контейнера опубликованы порты: $(docker port task02-app)"
fi

echo
echo "2. HTTP-интерфейс"
if [ "$(code "${URL}/health")" = "200" ]; then ok "/health -> 200"; else bad "/health не вернул 200"; fi

VER="$(curl -s "${URL}/version")"
if echo "${VER}" | grep -q '"version"'; then ok "/version -> ${VER}"; else bad "/version -> ${VER}"; fi

SUM="$(curl -s "${URL}/add?a=2&b=3")"
if echo "${SUM}" | grep -Eq '"result": ?5[,}]'; then ok "/add?a=2&b=3 -> ${SUM}"; else bad "/add?a=2&b=3 -> ${SUM}"; fi

NEG="$(curl -s "${URL}/add?a=-2&b=1")"
if echo "${NEG}" | grep -Eq '"result": ?-1[,}]'; then ok "/add?a=-2&b=1 -> ${NEG}"; else bad "/add?a=-2&b=1 -> ${NEG}"; fi

C="$(code "${URL}/add?a=2")"
if [ "${C}" = "400" ]; then ok "без параметра b -> 400"; else bad "без параметра b -> ${C}"; fi

C="$(code "${URL}/add?a=x&b=3")"
if [ "${C}" = "400" ]; then ok "нечисловой a -> 400"; else bad "нечисловой a -> ${C}"; fi

echo
echo "3. HTTPS"
C="$(code "http://${URL#https://}/health")"
case "${C}" in
  301|302|307|308) ok "HTTP перенаправляет на HTTPS (${C})" ;;
  *) bad "HTTP вернул ${C}" ;;
esac

echo
echo "4. Журнал доставок"
if [ -f "${STATE_DIR}/history.log" ]; then
  sed 's/^/  /' "${STATE_DIR}/history.log"
else
  bad "Нет history.log"
fi

echo
if [ "${FAIL}" -eq 0 ]; then echo "ИТОГ: все проверки пройдены"; else echo "ИТОГ: есть ошибки"; fi
exit "${FAIL}"
