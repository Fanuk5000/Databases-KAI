# PostgreSQL Lab 1.3: Робота з хмарною базою даних PostgreSQL (Supabase) через Python

Лабораторна робота з дисципліни **«Бази даних»**.  
Проєкт присвячено дослідженню клієнт-серверної архітектури без розгортання локального сервера СУБД, підключенню до керованої віддаленої бази даних у хмарі **Supabase** через мову програмування Python та бібліотеку **`psycopg`**, проєктуванню реляційних схем (`core`, `staging`) та таблиць (`device`, `sensor`, `raw_measurement`), маніпулюванню даними (DML), низькорівневому аналізу системних каталогів (`pg_database`, `pg_namespace`, `pg_class`) та ідентифікаторів `OID`, а також потоковому завантаженню даних із локального CSV-файлу через протокол **`COPY ... FROM STDIN`**.

---

## 📁 Структура проєкту

```text
lab1.3/
├── .env                 # Змінні оточення (DATABASE_URL пулера, приховано у .gitignore)
├── .gitignore           # Виключення віртуального оточення (.venv) та секретів (.env)
├── pyproject.toml       # Метадані проєкту та декларація залежностей (PEP 621)
├── requirements.txt     # Зафіксовані версії залежностей (psycopg2, python-dotenv)
├── README.md            # Головна документація проєкту, інструкції та протокол роботи
├── todo.md              # Покроковий чекліст виконання та методичний довідник
├── data/
    └── measurements.csv     # Датасет вимірів датчиків для потокового імпорту
├── src/
    └── db_connections.py    # Модуль підключення, діагностики сесій та каталогів OID
    └── db_creations.py      # Модуль DDL (схеми/таблиці), DML та потокового імпорту CSV
├── main.py              # Головна точка входу: безпечне оркестрування операцій
└── docs/
    └── report.md        # Повний академічний лабораторний звіт (19 пунктів + 23 питання)
```

---

## 🚀 Швидкий старт

### 1. Налаштування віртуального оточення Python

Перейдіть у директорію лабораторної роботи та створіть віртуальне оточення:

```bash
cd lab1.3
python3 -m venv .venv
source .venv/bin/activate
```

### 2. Встановлення залежностей

Встановіть необхідні пакети (`psycopg2`, `python-dotenv`) одним із способів:

**Варіант A: Через `requirements.txt` (рекомендовано)**
```bash
pip install -r requirements.txt
```

**Варіант B: Через `pyproject.toml`**
```bash
pip install .
```

*Примітка: При використанні `uv` можна запустити `uv pip install -r requirements.txt` або `uv sync`.*

### 3. Конфігурація підключення (`.env`)

Створіть файл `.env` у корені папки `lab1.3/`.  
Через відсутність підтримки IPv6 у більшості локальних провайдерів обов'язково використовуйте адресу **Session Pooler** (порт 5432):

```env
DATABASE_URL=postgresql://postgres.[YOUR-PROJECT-REF]:[YOUR-PASSWORD]@aws-0-[YOUR-REGION].pooler.supabase.com:5432/postgres
```

> **Важливо:**  
> - Хост пулера має вигляд `aws-0-...pooler.supabase.com` (наприклад, `aws-0-eu-central-1.pooler.supabase.com`).  
> - Користувач обов'язково включає префікс проєкту: `postgres.[project-ref]`.  
> - Порт: `5432` (Session pooler).  
> - Режим шифрування: TLS/SSL увімкнено за замовчуванням.

### 4. Запуск виконання

#### Основний запуск (через точка входу `main.py`):
```bash
python3 main.py
```
Скрипт перевіряє стан бази, виводить діагностику, безпечно створює структури та наповнює даними без ризику дублювання.

#### Модульний запуск:
```bash
# Перевірка з'єднання, вивід списку баз, схем та каталогів OID:
python3 db_connections.py

# Створення схем/таблиць, вставка записів, імпорт CSV та фінальна перевірка:
python3 db_creations.py
```

---

## 📜 Протокол виконання та логи сесії (Execution Logs)

Нижче наведено верифіковані логи фактичного прогону програми з реальними результатами з хмарної СУБД.

### 1. Інформація про базу даних до внесення змін

```text
Підключення до Supabase PostgreSQL...
Підключення успішно встановлено!

=== Іноформація про БД до будь-яких змін ===
Підключення до Supabase PostgreSQL...
Підключення успішно встановлено!

=== Інформація про підключення ===
Database:           postgres
User:               postgres
PID:                116187
PostgreSQL version: PostgreSQL 17.6 on x86_64-pc-linux-gnu, compiled by gcc (GCC) 15.2.0, 64-bit

=== Список баз даних ===
DB: postgres
DB: template0
DB: template1

=== Список схем ===
Schema: auth
Schema: extensions
Schema: graphql
Schema: graphql_public
Schema: information_schema
Schema: pg_catalog
Schema: pg_toast
Schema: pgbouncer
Schema: public
Schema: realtime
Schema: storage
Schema: vault

=== OID бази 'postgres' (pg_database) ===
OID: 5, DB: postgres

=== OID схем 'core' та 'staging' (pg_namespace) ===

=== OID таблиць через pg_class ===

=== Структура таблиць через information_schema.columns ===

Всі читання даних з БД пройшли успішно!
З'єднання закрито.
```

---

### 2. Створення схем, таблиць та додавання даних (DDL & DML)

```text
Підключення до Supabase PostgreSQL...
Підключення успішно встановлено!

--- Створення схем ---
Схеми 'core' та 'staging' успішно створено.

--- Створення таблиць ---
Таблиці 'core.device', 'core.sensor' та 'staging.raw_measurement' створено.

--- Перевірка створених таблиць ---
Таблиця: core.device
Таблиця: core.sensor
Таблиця: staging.raw_measurement

--- Структура таблиці core.sensor ---
Колонка: sensor_id, Тип: bigint, Nullable: NO
Колонка: device_id, Тип: bigint, Nullable: YES
Колонка: sensor_code, Тип: text, Nullable: NO
Колонка: quantity, Тип: text, Nullable: YES
Колонка: unit_symbol, Тип: text, Nullable: YES

--- Додавання початкових даних (DML) ---
Дані у 'core.device' та 'core.sensor' додано.
```

---

### 3. Потоковий імпорт CSV через протокол `COPY FROM STDIN`

```text
--- Імпорт measurements.csv через COPY FROM STDIN ---
CSV-файл успішно імпортовано в 'staging.raw_measurement'.

=== Перевірка вмісту таблиць ===
--- core.device ---
(1, 'MOTOR_01', 'DC Motor')

--- core.sensor ---
(1, 1, 'MOTOR_01_RPM', 'rotation_speed', 'rpm')

--- staging.raw_measurement (кількість записів) ---
Count: 4

--- staging.raw_measurement (всі записи) ---
('MOTOR_01_RPM', '2026-09-01T10:00:00+03:00', '1480.2')
('MOTOR_01_RPM', '2026-09-01T10:00:01+03:00', '1491.7')
('MOTOR_01_TORQUE', '2026-09-01T10:00:00+03:00', '2.34')
('MOTOR_01_TORQUE', '2026-09-01T10:00:01+03:00', '2.41')
```

---

### 4. Комплексна підсумкова перевірка (`run_final_check`)

```text
=== ПОВНА ДІАГНОСТИЧНА ПЕРЕВІРКА ===

=== PostgreSQL ===
PostgreSQL 17.6 on x86_64-pc-linux-gnu, compiled by gcc (GCC) 15.2.0, 64-bit

=== Connection ===
('postgres', 'postgres', 116189)

=== Schemas ===
('core',)
('staging',)

=== Tables ===
('core', 'device')
('core', 'sensor')
('staging', 'raw_measurement')

=== Devices ===
(1, 'MOTOR_01', 'DC Motor')

=== Sensors ===
(1, 1, 'MOTOR_01_RPM', 'rotation_speed', 'rpm')

=== Measurements ===
('MOTOR_01_RPM', '2026-09-01T10:00:00+03:00', '1480.2')
('MOTOR_01_RPM', '2026-09-01T10:00:01+03:00', '1491.7')
('MOTOR_01_TORQUE', '2026-09-01T10:00:00+03:00', '2.34')
('MOTOR_01_TORQUE', '2026-09-01T10:00:01+03:00', '2.41')

Все записано та прочитано успішно у БД!
З'єднання закрито.
```

---

### 5. Інспекція системних каталогів та OID створених об'єктів

```text
=== OID бази 'postgres' (pg_database) ===
OID: 5, DB: postgres

=== OID схем 'core' та 'staging' (pg_namespace) ===
OID: 17494, Schema: core
OID: 17495, Schema: staging

=== OID таблиць через pg_class ===
OID: 17497, Schema: core, Table: device
OID: 17505, Schema: core, Table: sensor
OID: 17517, Schema: staging, Table: raw_measurement

=== Структура таблиць через information_schema.columns ===
('core', 'device', 'device_id', 'bigint')
('core', 'device', 'device_name', 'text')
('core', 'device', 'model', 'text')
('core', 'sensor', 'sensor_id', 'bigint')
('core', 'sensor', 'device_id', 'bigint')
('core', 'sensor', 'sensor_code', 'text')
('core', 'sensor', 'quantity', 'text')
('core', 'sensor', 'unit_symbol', 'text')
('staging', 'raw_measurement', 'sensor_code', 'text')
('staging', 'raw_measurement', 'measured_at', 'text')
('staging', 'raw_measurement', 'value_text', 'text')
```

---

## 🧠 Ключові концепції та архітектурні висновки

1. **Хмарне підключення без локального сервера:**  
   Повний цикл розробки та маніпуляції базою реалізовано віддалено. Клієнтом виступає локальний скрипт Python, а сервером — хмарний кластер Supabase (AWS, PostgreSQL 17.6).
2. **Маршрутизація IPv4 через Session Pooler:**  
   Пряме підключення до `db.[ref].supabase.co` у безкоштовному тарифі вимагає IPv6. Використання Session Pooler на порті `5432` надає повноцінний IPv4-шлюз для з'єднання з будь-якої локальної мережі.
3. **Розділення схем `core` та `staging`:**  
   - `core` містить нормалізовану реляційну модель зі строгою типізацією та зв'язками `PRIMARY KEY` / `FOREIGN KEY`.  
   - `staging` слугує ізольованою буферною зоною для завантаження сирих текстових даних.
4. **Механізм `COPY ... FROM STDIN`:**  
   Оскільки сервер БД у хмарі не має доступу до локального жорсткого диска комп'ютера, стандартна команда `COPY ... FROM '/path'` не працює. Метод `cur.copy()` у `psycopg` зчитує файл на клієнті чанками по 8 КБ і потоком передає дані безпосередньо у відкритий сокет.
5. **Повна ідемпотентність коду:**  
   Скрипти захищені від повторних запусків:
   - Схеми та таблиці захищені через `IF NOT EXISTS`.
   - Вставка приладів і сенсорів перевіряє наявність через `SELECT` перед виконанням `INSERT`.
   - Таблиця `staging.raw_measurement` очищується через `TRUNCATE` перед кожним імпортом, забезпечуючи сталу кількість записів (`Count: 4`).
6. **Ізоляція системних каталогів та OID:**  
   - База `postgres`: OID = `5`.  
   - Схеми: `core` (OID = `17494`), `staging` (OID = `17495`).  
   - Таблиці: `core.device` (`17497`), `core.sensor` (`17505`), `staging.raw_measurement` (`17517`).

---

## 📚 Документація та звітність

- **Повний академічний звіт:** [`docs/report.md`](docs/report.md) — містить вичерпні відповіді на всі 23 контрольні питання, архітектурні діаграми, порівняльні таблиці та 19 обов'язкових пунктів за методичкою.
- **Методичний чекліст завдань:** [`todo.md`](todo.md) — детальний покроковий план проходження 36 етапів роботи.
