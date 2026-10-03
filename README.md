# Задание 02. Сборка, доставка и откат

HTTP-сервис на Python (Flask + gunicorn), который после успешных тестов
автоматически собирается, публикуется в GHCR и доставляется на VPS по digest.
Предыдущий выпуск сохраняется; откат выполняется вручную без пересборки.

Репозиторий: https://github.com/ppppana/task-02-service
Адрес сервиса: https://app.yohan-stock.duckdns.org

## Схема

```
GitHub (push в main)
  └─ ci.yml: Тесты → Сборка и публикация (GHCR) → Доставка на VPS
                                                      │ scp compose.yaml, deploy.sh
                                                      │ ssh: deploy.sh <образ@digest> <версия>
VPS
  Интернет → :443 → task01-caddy ─┬─ сеть internal → Gitea, PostgreSQL (задание 01)
                                  └─ сеть proxy    → task02-app:8000
```

| Компонент | Где | Порт | Наружу |
|---|---|---|---|
| task02-app (gunicorn) | Compose-проект `task-02` | 8000 | нет, только сеть `proxy` |
| Caddy (общий, из задания 01) | Compose-проект `gitea` | 80, 443 | да |

Своего Caddy у задания нет: порт 443 один, сайт добавлен в Caddyfile задания 01.

## Состав репозитория

| Путь | Назначение |
|---|---|
| `src/app.py` | сервис: `/health`, `/version`, `/add?a=&b=` |
| `tests/test_app.py` | 6 тестов pytest |
| `Dockerfile` | `python:3.12.8-slim`, непривилегированный пользователь, `ARG APP_VERSION` |
| `VERSION` | версия следующего выпуска |
| `compose.yaml` | проект `task-02`, образ из `${APP_IMAGE}`, внешняя сеть `proxy` |
| `.env.example` | пример `.env` (рабочий `.env` пишет `deploy.sh`) |
| `scripts/deploy.sh` | доставка образа по digest с проверкой |
| `scripts/check.sh` | проверка стенда |
| `.github/workflows/ci.yml` | тесты → сборка → GHCR → доставка |
| `.github/workflows/rollback.yml` | ручной откат без сборки |
| `evidence/` | журналы CI, вывод проверок, скриншот |

## Зависимости от common/ и задания 01

- Docker-сеть `proxy` (внешняя, общая для reverse proxy и публикуемых сервисов).
- Caddy задания 01 подключён к сети `proxy`, в его Caddyfile есть блок:
  ```
  {$APP_DOMAIN} {
      encode gzip
      reverse_proxy task02-app:8000
  }
  ```
  `APP_DOMAIN` задаётся в `.env` задания 01.

## Ручные действия (один раз)

1. На VPS: `docker network create proxy`.
2. На VPS: `mkdir -p /opt/task-02/app` (каталог состояния `deploy.sh` создаёт сам).
3. Подключить Caddy задания 01 к сети `proxy`, добавить блок сайта и
   `APP_DOMAIN` в `.env`, пересоздать Caddy: `docker compose up -d caddy`.
4. Создать SSH-ключ для CI, публичную часть добавить в `authorized_keys` на VPS.
5. В GitHub: Settings → Secrets and variables → Actions — секреты
   `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY`.
6. Проверить, что пакет в GHCR публичный (VPS скачивает образ без авторизации).

## Скрипты

**`deploy.sh <образ@sha256:...> <ожидаемая версия>`** — вызывается из CI.
Переменные (необязательно): `APP_DIR` (по умолчанию `/opt/task-02/app`),
`STATE_DIR` (по умолчанию `/opt/task-02/state`).
Принимает только ссылку по digest; блокирует параллельный запуск (`flock`);
пишет `.env`, делает `pull` и `compose up`; до 60 секунд ждёт, пока `/health`
ответит, а `/version` совпадёт с ожидаемой. Только после успешной проверки
обновляет `state/current-image`, `state/previous-image` и `state/history.log`.
Если проверка не прошла — возвращает последний рабочий выпуск и завершается с кодом 1.

**`check.sh [URL]`** — запускается на VPS. Проверяет совпадение работающего
digest с сохранённым, наличие точки отката, отсутствие опубликованных портов,
все HTTP-ответы (включая 400) и перенаправление HTTP → HTTPS, выводит журнал
доставок. Код 0 — всё в порядке.

## Проверка

```
bash /opt/task-02/app/check.sh
curl -s https://app.yohan-stock.duckdns.org/version
curl -s "https://app.yohan-stock.duckdns.org/add?a=2&b=3"
docker inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' task02-app
```

## Выпуск, ошибка, откат

- **Обычный выпуск:** изменить код, поднять `VERSION`, `git push` в `main`.
  CI выполнит тесты, соберёт образ с тегами `<версия>` и `<commit>` и меткой
  `org.opencontainers.image.revision`, доставит его по digest. Текущий выпуск
  станет точкой отката. Сейчас подготовлена версия `1.0.0-D`.
- **Ошибка в коде:** падает этап «Тесты», сборка и доставка пропускаются,
  на VPS остаётся предыдущая версия.
- **Откат:** Actions → Rollback → Run workflow. Пустое поле — откат на
  `state/previous-image`; можно указать конкретный образ по digest. Версия
  берётся из метки образа, развёртывание идёт тем же `deploy.sh`, затем
  проверяются `/health`, `/version`, сложение и совпадение digest.
- Доставка и откат используют общую группу `concurrency: task02-deploy`
  и никогда не выполняются одновременно.
- Изменения только в `*.md` и `evidence/` CI не запускают (`paths-ignore`).
