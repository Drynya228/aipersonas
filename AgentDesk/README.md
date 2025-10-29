# AgentDesk

AgentDesk — настольное macOS-приложение (SwiftUI), помогающее оркестрировать виртуальную рабочую силу на базе ИИ-персон. Этот репозиторий содержит каркас MVP с модульной архитектурой, заготовками сервисов, документацией и тестовой инфраструктурой.

## 🚀 Быстрый старт

### Требования окружения
- macOS 13 или новее (тестирование ведётся на 13.6 и 14.4).
- Xcode 15.0+ с установленными командными инструментами (`xcode-select --install`).
- Swift 5.9+ (поставляется вместе с Xcode 15).
- Homebrew для вспомогательных утилит (`/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`).
- Доступ к интернету для загрузки зависимостей и активации OpenAI API.

### Подготовка репозитория
```bash
git clone <repo-url>
cd AgentDesk
make bootstrap             # скачиваем SwiftPM зависимости, создаём локальное хранилище, прогоняем stub-миграции
make lint                   # опционально: проверка форматирования (пропускается, если swift-format не установлен)
make test                   # убедиться, что модульные тесты проходят
```

> Примечание: первый запуск `make bootstrap` создаст каталог `.build/.agentdesk` для SQLite и отметит файл `.bootstrap-complete`. Повторный вызов безопасен.

### Настройка секретов и конфигов
1. **OpenAI** — сохраните ключ в Keychain (пример для Responses API):
   ```bash
   security add-generic-password -a agentdesk -s openai -w "sk-..." -U
   ```
2. **Realtime/TTS** — используйте тот же ключ или отдельный скоупированный. Для удобства можно добавить тег `openai-realtime`:
   ```bash
   security add-generic-password -a agentdesk -s openai-realtime -w "sk-..." -U
   ```
3. **Payments-провайдер** (песочница):
   ```bash
   security add-generic-password -a agentdesk -s payments-sandbox -w "pay-sandbox-key" -U
   ```
4. Создайте файл `AgentDesk/.env.local` (или используйте готовый `Docs/config/.env.example`, если подключите его сами) и укажите несекретные параметры:
   ```env
   SOURCING_MODE=dry-run
   DEFAULT_CLIENT_COLLECTION=demo-client
   VOICE_OUTPUT_FOLDER=~/Library/Application\ Support/AgentDesk/Voice
   ```
5. Проверьте наличие записей: `security find-generic-password -a agentdesk -s openai`.

### Сборка и запуск приложения
1. Откройте проект в Xcode: `xed .` (или `open AgentDesk.xcodeproj`, если вы создаёте его вручную).
2. Выберите схему **AgentDeskApp** и цель **My Mac (Designed for Mac)**.
3. Сборка: ⌘B. Если сборка прошла успешно, Xcode автоматически генерирует `.app` внутри DerivedData.
4. Запуск: ⌘R. При первом старте появится мастер настройки (импортер персон, RAG и тестовый звонок).
5. Для CLI-запуска в headless-режиме используйте `swift run AgentDeskApp` (ограниченный режим без UI, полезен для отладки сервисов).

### Проверка готовности после запуска
- Экран **Dashboard** должен отображать демо-метрики и последнее решение RevenueWatch.
- В разделе **Settings → Connectivity** убедитесь, что Keychain-ключи отмечены зелёными индикаторами.
- Выполните тестовый запрос TTS через кнопку «Preview Voice» в карточке персоны — файл попадёт в `~/Library/Application Support/AgentDesk/Voice`.
- На вкладке **Tasks** создайте задачу «Hello World» и проведите её по колонкам, чтобы убедиться, что сессии и хранилище работают.

### Хранение секретов и безопасность
- Все секреты живут только в Keychain. При удалении приложения используйте `security delete-generic-password -a agentdesk -s <service>`.
- `.env.local` игнорируется Git и содержит только несекретные параметры (режимы, идентификаторы коллекций).
- Лимиты токенов/минут и фильтры можно настраивать на вкладке Settings. Для ручного редактирования существует файл `~/Library/Application Support/AgentDesk/config.json`.

### Дев-режим и симуляторы сервисов
- `make dev` — быстрая сборка Debug и запуск stub-сервисов (RAG ingest, payments webhook, voice loopback). Команда выводит PID процессов и путь к логам.
- Логи сервиса выводятся в Xcode Console и сохраняются в `~/Library/Logs/AgentDesk/*.log`.
- Переключатель `Sourcing Mode (dry-run/live)` и включение webhook-тестера находятся в Settings.

## 📱 Основные экраны
- **Dashboard** — KPI (Jobs/Day, RPM, Accept Rate, Rev Cost и др.) + лента решений RevenueWatch.
- **Personas** — полноценный CRUD, предпрослушка TTS, быстрый просмотр навыков и ограничений.
- **Tasks** — Канбан (Intake → In-progress → Validate → Deliver) с кнопкой продвижения задачи и отображением лимитов.
- **Chat/Calls** — поток сообщений по задаче, симуляция звонка и мгновенное появление записи/транскрипта.
- **Artifacts** — версии артефактов, экспорт ZIP, запросы к локальному RAG с ранжированными фрагментами.
- **Settings** — Keychain-ссылки, лимиты токенов, переключатель sourcing dry-run/live, импорт RAG, compliance-сканы, платежи.

## 🧩 Архитектура
```
AgentDesk/
  AgentDeskApp/         # UI SwiftUI
  AgentCore/            # Модели, сессии, оркестратор
  ToolHub/              # Реестр функций, JSON-схемы, исполнители
  Voice/                # Realtime/TTS заглушки
  RAG/                  # Индексация и выдача документов
  Storage/              # Хранилище (GRDB-интерфейс, InMemory stub)
  RevenueWatch/         # Метрики и пороговая логика
  Payments/             # Инвойсы, поллинг, квитанции
  Compliance/           # Санитайзер, freeze, политики
  Docs/                 # Персоны, чек-листы, офферы, SOP
  CI/                   # Скрипты CI (lint/test/build)
  Tests/                # XCTest
  Makefile
```

## 📥 RAG
- Импорт PDF/MD/HTML — вкладка RAG на экране Artifacts.
- Индексация выполняется локально (FAISS/SQLite). В MVP подключена заглушка (`RAGService`).
- Коллекции именуются по клиенту или персоне. Настройте их в Settings.

## 🧠 Персоны
- Формат JSON (см. `Docs/personas`).
- Поля: `name`, `role`, `tone`, `voicePreset`, `voiceRate`, `skills`, `tools_allowed`, `rag_collections`, `constraints`.
- CRUD реализуется через `PersonasView`. Предпрослушка TTS использует `VoiceService.previewSpeech`.

## 🔍 Sourcing & Bid Engine
- Сервис интеграций включает режимы `dry-run` (по умолчанию) и `live`. Переключение в Settings → Sourcing.
- Лиды отображаются в Tasks (колонка Intake). Офферы генерируются на базе шаблонов из `Docs/proposals`.

## 💰 Payments
- Настройка ограниченных API-ключей в Settings.
- `billing.create_invoice` и `billing.poll` вызываются через ToolHub.
- Вывод средств — **только вручную** владельцем (см. SOP).

## 📊 RevenueWatch
- Метрики обновляются по требованию (меню ⌘R) и агрегируются по окну (`1d/7d`).
- При срабатывании порогов автоматически формируются решения с рекомендациями (`routing.rebalance`, «tighten-intake» и др.).
- История решений доступна на Dashboard, а также через `RevenueMetricsService.recentDecisions()`.

## 🛡️ Комплаенс
- `ComplianceService.scan` — базовый санитайзер. Перед отправкой писем/офферов прогоняются тексты.
- Kill-switch `admin.freeze` доступен в Settings.

## 🧪 Тестирование
- `make test` — запуск XCTest (покрывает Sessions, ToolHub, RAG, Compliance, Payments, Voice, RevenueWatch).
- `make lint` — попытка запустить `swift-format` (пропустит, если утилита не установлена).

## 📦 Поставка
- В разделе Artifacts нажмите **Export ZIP** — файл появится во временной директории и отобразится в интерфейсе.
- Для проверки email-драфта используйте инструмент `email.draft` (через ToolHub или Sessions).

## 🧭 Первый E2E сценарий
1. Создайте персону Manager и Worker в Personas.
2. Импортируйте PDF → привяжите к коллекции клиента.
3. Создайте задачу «EN→RU лендинг» → Worker выпускает черновик.
4. Validator применяет чек-лист `translate.yml` → вердикт Accept.
5. Запустите Realtime-звонок (30-60 сек), просмотрите запись и транскрипт.
6. `routing.rebalance` и `market.search` появятся в логах RevenueWatch при низких KPI.
7. Сформируйте Invoice и отметьте оплату через webhook-симулятор.
8. Нажмите Deliver → получите ZIP с артефактами.

## 🔍 Логи
- Приложение: `~/Library/Logs/AgentDesk/app.log`.
- RevenueWatch: `~/Library/Logs/AgentDesk/revenue.log`.
- Voice: `~/Library/Logs/AgentDesk/voice.log`.

## 📡 CI
- GitHub Actions/любая CI система может вызывать скрипты из `CI/` (`lint.sh`, `test.sh`, `build.sh`).

## ❓ FAQ
- **Где хранятся ключи?** В Keychain macOS.
- **Как включить live-подачу офферов?** Settings → Sourcing → переключить `dry-run` → `live` (требует подтверждения).
- **Можно ли отправить деньги ботам?** Нет. Только инвойсы/квитанции. Вывод — вручную владельцем.
- **Как почистить PII?** Используйте Compliance → Sanitize. Подробности — `Docs/sop/pii-leak.md`.

## 📐 Scale
- Рекомендуемый стек: Kubernetes runner + Helm chart + Vault + ArgoCD.
- Настройки namespaces и квот описаны в разделе `Scale` README (расширение v1.1/v1.2).

## 🧾 SOP
- Инциденты описаны в `Docs/sop/*.md` (ключи, PII, freeze, платежи, лимиты API).

