# Oracle Free Tier Hunter

> 🌐 **Language / Язык:** [English](README.md) | Русский

Автоматизированный охотник за бесплатным инстансом Oracle Cloud **VM.Standard.A1.Flex** (4 OCPU / 24 GB RAM).

Бесплатные ARM-инстансы Oracle Always Free пользуются огромным спросом и почти всегда недоступны с ошибкой "Out of host capacity". Единственный надёжный способ получить один — пробовать снова и снова, пока не откроется слот. Этот инструмент делает это автоматически, 24/7, без необходимости держать компьютер включённым.

---

## Как это работает

1. GitHub Actions запускается по расписанию (cron) каждые 30 минут
2. Устанавливает OCI CLI и настраивает его из GitHub Secrets
3. **Автоматически получает Availability Domains** для твоего региона — ничего хардкодить не нужно
4. Делает до 20 попыток за один запуск, ротируя по всем AD
5. При успехе или критической ошибке отправляет уведомление в Telegram
6. При обычном ответе "нет мест" — завершается молча и ждёт следующего запуска

---

## Структура репозитория

```
.
├── .github/
│   └── workflows/
│       └── hunter.yml       # GitHub Actions workflow (запускается каждые 30 мин)
└── oracle_sniper.sh         # Bash-скрипт для локального / ручного запуска
```

---

## Настройка

### Шаг 1 — OCI API ключ

Если у тебя ещё нет API ключа:

1. Открой [Oracle Cloud Console](https://cloud.oracle.com) → нажми на иконку профиля (правый верхний угол) → **My profile**
2. Прокрути до **API keys** → **Add API key**
3. Выбери **Generate API key pair** → скачай оба ключа
4. Oracle покажет превью конфига — скопируй оттуда `fingerprint`, `tenancy`, `user` и `region`

> Официальная документация: [Required Keys and OCIDs](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm)

### Шаг 2 — Найди OCID ресурсов

| Значение | Где найти |
|----------|-----------|
| `OCI_COMPARTMENT_ID` | Иконка профиля → **Tenancy** → скопируй **OCID** (для root compartment совпадает с tenancy) |
| `OCI_SUBNET_ID` | **Networking → Virtual Cloud Networks** → твой VCN → **Subnets** → скопируй OCID |
| `OCI_IMAGE_ID` | **Compute → Images** → выбери ОС (например Ubuntu 22.04 Minimal, ARM-совместимый) → скопируй OCID |

### Шаг 3 — GitHub Secrets

Перейди в репозиторий: **Settings → Secrets and variables → Actions → New repository secret**

| Secret | Описание |
|--------|----------|
| `OCI_USER_OCID` | OCID твоего пользователя (`ocid1.user...`) |
| `OCI_TENANCY_OCID` | OCID тенанси (`ocid1.tenancy...`) |
| `OCI_FINGERPRINT` | Отпечаток API-ключа (формат: `xx:xx:xx:...`) |
| `OCI_REGION` | Целевой регион, например `eu-frankfurt-1`, `us-ashburn-1` |
| `OCI_API_KEY` | Полное содержимое приватного ключа (включая `-----BEGIN/END-----`) |
| `OCI_SSH_PUB_KEY` | Содержимое публичного SSH-ключа (`~/.ssh/id_rsa.pub` или аналог) |
| `OCI_COMPARTMENT_ID` | OCID compartment (обычно совпадает с tenancy для root) |
| `OCI_SUBNET_ID` | OCID subnet в целевом регионе |
| `OCI_IMAGE_ID` | OCID образа ОС (должен быть ARM-совместимым для A1.Flex) |
| `TELEGRAM_TOKEN` | Токен Telegram-бота |
| `TELEGRAM_TO_ID` | Твой Telegram chat ID |

### Шаг 4 — Активация workflow

Запушь репозиторий на GitHub. Открой вкладку **Actions** — должен появиться `Oracle Cloud Hunter`. Первый раз запусти вручную кнопкой **Run workflow**, чтобы проверить что credentials корректны.

---

## Telegram уведомления

Бот пишет **только при реальном событии** — не при каждом запуске:

- `✅` — инстанс успешно создан
- `⚠️` — ошибка выполнения workflow (проблема с авторизацией, лимит и т.д.)

Штатные запуски "нет мест" — молчат.

### Как настроить Telegram бота

1. Открой Telegram → найди **@BotFather** → отправь `/newbot`
2. Следуй инструкциям — в конце BotFather выдаст токен вида `7412345678:AAHdqTcvCH...` → это твой `TELEGRAM_TOKEN`
3. Начни чат с ботом (отправь ему любое сообщение)
4. Открой в браузере (замени `<TOKEN>` на свой):
   ```
   https://api.telegram.org/bot<TOKEN>/getUpdates
   ```
5. Найди в ответе `"chat": { "id": 123456789 }` → это твой `TELEGRAM_TO_ID`

---

## Локальный запуск (oracle_sniper.sh)

Требуется установленный OCI CLI (`pip install oci-cli` + `oci setup config`).

```bash
# Обязательные переменные окружения
export OCI_COMPARTMENT_ID="ocid1.tenancy..."
export OCI_IMAGE_ID="ocid1.image..."
export OCI_SUBNET_ID="ocid1.subnet..."

# Запуск
bash oracle_sniper.sh
```

Опциональные переменные окружения:

| Переменная | По умолчанию | Описание |
|------------|--------------|----------|
| `SSH_KEY_PATH` | `~/oracle_key.pub` | Путь к публичному SSH-ключу |
| `LOG_FILE` | `~/oracle_sniper.log` | Путь к основному логу |
| `ERROR_LOG` | `~/oracle_unknown_error.log` | Лог неизвестных ошибок |
| `SLEEP_INTERVAL` | `60` | Пауза между попытками при "нет мест" (сек) |
| `MAX_ATTEMPTS` | `0` (бесконечно) | Лимит попыток перед остановкой |
| `NTFY_TOPIC` | — | Топик [ntfy.sh](https://ntfy.sh) для push-уведомлений |

---

## Важные замечания

**Бесплатный лимит GitHub Actions:**
- Публичные репозитории: **неограниченные минуты** — рекомендуется
- Приватные репозитории: 2 000 мин/месяц бесплатно. Один запуск ~5 мин → ~7 200 мин/месяц → сделай репо публичным или уменьши частоту cron

**Авто-отключение:** GitHub отключает scheduled workflows если в репозитории нет активности **60 дней**. Раз в месяц запускай workflow вручную кнопкой, чтобы этого не случилось.
