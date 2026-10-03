# RESULT — задание 02. Сборка, доставка и откат

## 1. Общее

- Дата: 2026-10-03
- Затрачено: 3ч 

## 2. Адреса и ссылки

- Сервис: https://app.yohan-stock.duckdns.org (`/health`, `/version`, `/add?a=2&b=3`)
- Репозиторий: https://github.com/ppppana/task-02-service
- Финальный commit исправного кода: `3e821bd` (возврат `add()`, подготовка `1.0.0-D`)
- Ошибочная ревизия: https://github.com/ppppana/task-02-service/commit/6b4d749aede0f352982507fc0e47788010ef8c70

Запуски CI/CD:

| Запуск | Ссылка | Результат |
|---|---|---|
| Выпуск A | https://github.com/ppppana/task-02-service/actions/runs/36594351360 | успешно |
| Выпуск B | https://github.com/ppppana/task-02-service/actions/runs/36595990837 | успешно |
| Ошибка в `add()` (C) | https://github.com/ppppana/task-02-service/actions/runs/36602630175 | тесты упали, сборка и доставка пропущены |
| Откат на A | https://github.com/ppppana/task-02-service/actions/runs/36603984069 | успешно, без сборки |

## 3. Версия — commit — digest

| Версия | Commit | Digest образа |
|---|---|---|
| 1.0.0-A | `b2dd12ede3e78118f0265e62808a5d8f9cae9c74` | `sha256:0c3a7f54cde2d3e8ee8f14bd6ed918a5f15ebe381ab0a9144f7acb82ec8ca5f8` |
| 1.0.0-B | `00b92b4f82099bd02bbbb64a2d3d387ac6ee4c04` | `sha256:97a365193edf33e1b35e88c25e97b3132200112ff3add076b3a1a0145ed7d966` |
| 1.0.0-C | `6b4d749aede0f352982507fc0e47788010ef8c70` | — (не собран) |

## 4. Сервисы и стенд

- Образ приложения: `ghcr.io/ppppana/task-02-service` (база `python:3.12.8-slim`), только по digest
- Reverse proxy: общий `caddy:2.8.4-alpine` из задания 01, сеть `proxy`
- VPS: Aeza, 2 vCPU, 3,8 ГБ RAM, 59 ГБ SSD, Ubuntu 24.04.5 LTS

## 5. Требования

| № | Требование | Статус | Подтверждение |
|---|---|---|---|
| 1 | Сервис: `/health`, `/version`, `/add`, 400 на ошибки | выполнено | `evidence/task02-check.txt` (раздел 2) |
| 2 | Тесты, Dockerfile, Compose, HTTPS через Caddy | выполнено | `tests/`, `Dockerfile`, `compose.yaml`; `task02-check.txt` (раздел 3) |
| 3 | Тесты → сборка → GHCR → доставка по digest, связь с commit | выполнено | `evidence/ci-1-release-A.zip`, метка `revision` в `task02-check.txt` |
| 4 | Проверка после доставки, сохранение предыдущего digest, запрет параллельных доставок, секреты | выполнено | `ci-2-release-B.zip` («Предыдущий выпуск сохранён»), `concurrency` в workflow, `flock` в `deploy.sh` |
| 5 | Версии A и B; ошибка в сложении блокирует доставку, на VPS остаётся B | выполнено | `ci-3-failed-C.zip` (только тесты, `2 failed`), `failed-tests-C.txt`, журнал доставок без C |
| 6 | Ручной откат на сохранённый digest A без сборки | выполнено | `ci-4-rollback-A.zip` (один этап, digest `0c3a7f54...`), `history.log` |

## 6. Проверка за пять минут

1. `curl -s https://app.yohan-stock.duckdns.org/version` → `{"version":"1.0.0-B"}`.
2. На VPS: `bash /opt/task-02/app/check.sh` → все `[ OK ]`, код 0.
3. Actions: запуск C — «Тесты» красные, остальные этапы пропущены.
4. Actions → Rollback → Run workflow (поле пустое) → зелёный.
5. `curl -s .../version` → `1.0.0-A`; `curl -s ".../add?a=2&b=3"` → `{"result":5}`;
   `cat /opt/task-02/state/current-image` → digest `sha256:0c3a7f54...`, как у выпуска A.

## 7. Проблемы и ограничения

- Сервис публикуется через Caddy задания 01: при остановке проекта задания 01
  приложение недоступно по HTTPS (сам контейнер продолжает работать).
- После проверки отката стенд возвращён в состояние «работает B, точка отката A»
  служебным откатом на B (`history.log`, 2026-09-29 20:28). Журнал этого
  запуска в GitHub удалён по ошибке; подтверждение — `history.log` в `task02-check.txt`.
- При работе с VPS SSH обрывался на обмене ключами: домашний канал не пропускал
  пакеты полного размера. Решено уменьшением MTU адаптера на рабочем компьютере
  до 1280; на стенд и CI не влияет.
- Незавершённых пунктов нет.
