#!/usr/bin/env bash
# Доставка образа приложения задания 02 по digest.
#
# Использование:
#   bash deploy.sh <образ@sha256:...> <ожидаемая версия>
# Пример:
#   bash deploy.sh ghcr.io/ppppana/task-02-service@sha256:abc... 1.0.0-A
#
# Переменные (необязательные):
#   APP_DIR   — каталог с compose.yaml (по умолчанию /opt/task-02/app)
#   STATE_DIR — каталог состояния      (по умолчанию /opt/task-02/state)
#
# Файлы состояния (только на сервере, в архив не входят):
#   state/current-image  — последний выпуск, прошедший проверку
#   state/previous-image — выпуск до него (цель ручного отката)
#   state/history.log    — журнал всех успешных доставок
set -euo pipefail

IMAGE="${1:?укажите образ с digest}"
EXPECTED_VERSION="${2:?укажите ожидаемую версию}"
APP_DIR="${APP_DIR:-/opt/task-02/app}"
STATE_DIR="${STATE_DIR:-/opt/task-02/state}"

log() { echo "[$(date '+%F %T %Z')] $*"; }

# Разрешаем только ссылку на конкретный digest, не тег
case "${IMAGE}" in
  *@sha256:*) ;;
  *) log "ОШИБКА: образ нужно указать по digest (@sha256:...)"; exit 2 ;;
esac

cd "${APP_DIR}"
mkdir -p "${STATE_DIR}"

# Защита от одновременного запуска на самом сервере
# (дополнительно к concurrency в GitHub Actions)
exec 9>"${STATE_DIR}/deploy.lock"
flock -n 9 || { log "ОШИБКА: другая доставка уже выполняется"; exit 3; }

# Последний проверенный выпуск — до изменений
PREV_GOOD=""
if [ -f "${STATE_DIR}/current-image" ]; then
  PREV_GOOD="$(cat "${STATE_DIR}/current-image")"
fi

log "Разворачиваю: ${IMAGE}"
log "Ожидаемая версия: ${EXPECTED_VERSION}"
docker pull "${IMAGE}"
echo "APP_IMAGE=${IMAGE}" > .env
docker compose up -d --force-recreate

# Проверка изнутри контейнера: /health отвечает, /version совпадает
check() {
  docker compose exec -T app python -c '
import json, sys, urllib.request
base = "http://127.0.0.1:8000"
urllib.request.urlopen(base + "/health", timeout=3)
v = json.load(urllib.request.urlopen(base + "/version", timeout=3))["version"]
print("version:", v)
sys.exit(0 if v == sys.argv[1] else 1)
' "${EXPECTED_VERSION}"
}

log "Проверяю /health и /version"
ok=0
for _ in $(seq 1 30); do
  if check >/dev/null 2>&1; then ok=1; break; fi
  sleep 2
done

if [ "${ok}" -ne 1 ]; then
  log "ОШИБКА: новый выпуск не прошёл проверку за 60 секунд"
  docker compose logs --tail 30 app || true
  if [ -n "${PREV_GOOD}" ]; then
    log "Возвращаю последний рабочий выпуск: ${PREV_GOOD}"
    echo "APP_IMAGE=${PREV_GOOD}" > .env
    docker compose up -d --force-recreate
  fi
  exit 1
fi

# Выпуск прошёл проверку — только теперь обновляем состояние
if [ -n "${PREV_GOOD}" ] && [ "${PREV_GOOD}" != "${IMAGE}" ]; then
  echo "${PREV_GOOD}" > "${STATE_DIR}/previous-image"
  log "Предыдущий выпуск сохранён: ${PREV_GOOD}"
fi
echo "${IMAGE}" > "${STATE_DIR}/current-image"
echo "$(date '+%F %T %Z') ${EXPECTED_VERSION} ${IMAGE}" >> "${STATE_DIR}/history.log"

log "Готово: работает версия ${EXPECTED_VERSION}"
docker compose ps
