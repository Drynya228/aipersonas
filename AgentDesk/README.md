# AgentDesk

AgentDesk — настольное macOS-приложение (SwiftUI), помогающее оркестрировать виртуальную рабочую силу на базе ИИ-персон. Этот репозиторий содержит каркас MVP с модульной архитектурой, заготовками сервисов, документацией и тестовой инфраструктурой.

## 🚀 Быстрый старт

### Требования
- macOS 13+
- Xcode 15+
- Swift 5.9+
- Homebrew (для вспомогательных утилит)

### Установка
1. Склонируйте репозиторий и откройте `AgentDesk.xcodeproj` (создаётся автоматически при первом открытии папки `AgentDesk` в Xcode).
2. Запустите `make bootstrap`, чтобы установить зависимости, применить миграции SQLite и подготовить локальные конфиги.
3. Откройте схему `AgentDeskApp` и соберите проект (⌘+B).
4. Запустите приложение (⌘+R).

### Хранение секретов
- API-ключи OpenAI и платёжного провайдера сохраняются исключительно в Keychain (`security add-generic-password -a agentdesk -s openai -w <KEY>`).
- `.env` используется только для несекретных настроек (идентификаторы коллекций, включение dry-run и т.д.).
- Проверить наличие секретов: `security find-generic-password -a agentdesk -s openai`.

### Дев-режим
- `make dev` — сборка Debug и запуск вспомогательных симуляторов (RAG, Payments, Voice).
- Логи сервиса отображаются в Xcode Console и в файлах `~/Library/Logs/AgentDesk/*.log`.
- Переключатель `Sourcing Dry-Run` расположен на экране Settings.

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

