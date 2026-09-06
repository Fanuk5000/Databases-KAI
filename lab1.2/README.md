# PostgreSQL Lab 1.2: Connections, Schemas & System Catalogs

Лабораторна робота з дисципліни «Бази даних». Проєкт присвячено дослідженню клієнт-серверної архітектури СУБД PostgreSQL, роботі зі схемами (просторами імен), механізму розв'язання імен через `search_path`, аналізу внутрішніх системних каталогів (`pg_catalog`, `information_schema`), безпечній перевірці об'єктів через `to_regclass()`, а також дослідженню паралельних клієнтських сесій і серверних процесів (`PID`) через динамічне представлення `pg_stat_activity`.

---

## Структура проєкту

```text
lab1.2/
├── .gitignore
├── README.md                   # Документація проєкту та логи виконання
├── todo.md                     # Покроковий чекліст та інструкція завдань
├── savings.txt                 # Сирі збережені логи термінальної сесії
├── docker-compose.yml          # Швидкий запуск оточення PostgreSQL 18.6 у Docker
├── sql/
│   ├── 01_schema.sql           # Створення схеми experiment, таблиці test_result та наповнення
│   ├── 02_search_path.sql      # Дослідження поведінки пошуку схем search_path
│   ├── 03_introspection.sql    # Опитування information_schema, pg_catalog та regclass
│   └── 04_monitoring.sql       # Моніторинг процесів і сесій через pg_stat_activity
└── docs/
    └── report.md               # Повний академічний лабораторний звіт
```

---

## Швидкий старт

### Варіант 1: Через Docker Compose

```bash
# Запуск контейнера PostgreSQL
docker compose up -d

# Підключення до бази через psql
docker compose exec -it postgres psql -U lab_student -d lab_measurements
```

### Варіант 2: Локальне виконання через `psql`

```bash
# 1. Створення схеми experiment та таблиці з даними
psql -U lab_student -d lab_measurements -f sql/01_schema.sql

# 2. Тестування поведінки search_path
psql -U lab_student -d lab_measurements -f sql/02_search_path.sql

# 3. Виконання запитів інтроспекції (каталоги та regclass)
psql -U lab_student -d lab_measurements -f sql/03_introspection.sql

# 4. Моніторинг активних бекендів
psql -U lab_student -d lab_measurements -f sql/04_monitoring.sql
```

---

## Протокол виконання та логи сесії (Execution Logs)

Нижче наведено верифіковані логи фактичного виконання завдань згідно з `savings.txt`.

### 1. Інформація про поточну сесію та підключення

```text
lab_measurements=> SELECT current_database(), current_user, current_schema();
 current_database | current_user | current_schema
------------------+--------------+----------------
 lab_measurements | lab_student  | public
(1 row)

lab_measurements=> \conninfo
           Connection Information
      Parameter       |        Value
----------------------+---------------------
 Database             | lab_measurements
 Client User          | lab_student
 Socket Directory     | /var/run/postgresql
 Server Port          | 5432
 Options              |
 Protocol Version     | 3.0
 Password Used        | false
 GSSAPI Authenticated | false
 Backend PID          | 8913
 SSL Connection       | false
 Superuser            | off
 Hot Standby          | off
(12 rows)

lab_measurements=> SHOW server_version;
 server_version
----------------
 18.6
(1 row)

lab_measurements=> SHOW search_path;
   search_path
-----------------
 "$user", public
(1 row)
```

---

### 2. Створення схеми `experiment` та таблиці `test_result`

```text
lab_measurements=> \dn
        List of schemas
    Name    |       Owner
------------+-------------------
 core       | lab_student
 experiment | lab_student
 public     | pg_database_owner
 staging    | lab_student
(4 rows)

lab_measurements=> \dt experiment.*
                 List of tables
   Schema   |    Name     | Type  |    Owner
------------+-------------+-------+-------------
 experiment | test_result | table | lab_student
(1 row)

lab_measurements=> \d experiment.test_result
                         Table "experiment.test_result"
     Column      |  Type   | Collation | Nullable |           Default
-----------------+---------+-----------+----------+------------------------------
 result_id       | bigint  |           | not null | generated always as identity
 experiment_name | text    |           | not null |
 measured_value  | numeric |           |          |
 unit_symbol     | text    |           |          |
Indexes:
    "test_result_pkey" PRIMARY KEY, btree (result_id)

lab_measurements=> SELECT * FROM experiment.test_result;
 result_id | experiment_name | measured_value | unit_symbol
-----------+-----------------+----------------+-------------
         1 | Voltage test    |           12.4 | V
         2 | Current test    |            1.8 | A
         3 | Speed test      |           1480 | rpm
(3 rows)
```

---

### 3. Дослідження просторів імен та `search_path`

```text
lab_measurements=> SHOW search_path;
   search_path
-----------------
 "$user", public
(1 row)

lab_measurements=> SELECT * FROM test_result;
ERROR:  relation "test_result" does not exist
LINE 1: SELECT * FROM test_result;

lab_measurements=> SET search_path TO experiment, public;
SET

lab_measurements=> SELECT * FROM test_result;
 result_id | experiment_name | measured_value | unit_symbol
-----------+-----------------+----------------+-------------
         1 | Voltage test    |           12.4 | V
         2 | Current test    |            1.8 | A
         3 | Speed test      |           1480 | rpm
(3 rows)
```

---

### 4. Інтроспекція метаданих: `information_schema` vs `pg_catalog`

```text
lab_measurements=>   SELECT
      table_schema,
      table_name,
      column_name,
      data_type
  FROM information_schema.columns
  WHERE table_schema = 'experiment'
    AND table_name = 'test_result'
  ORDER BY ordinal_position;
 table_schema | table_name  |   column_name   | data_type
--------------+-------------+-----------------+-----------
 experiment   | test_result | result_id       | bigint
 experiment   | test_result | experiment_name | text
 experiment   | test_result | measured_value  | numeric
 experiment   | test_result | unit_symbol     | text
(4 rows)

lab_measurements=>   SELECT
      c.oid,
      n.nspname AS schema_name,
      c.relname,
      c.relkind
  FROM pg_class AS c
  JOIN pg_namespace AS n ON n.oid = c.relnamespace
  WHERE n.nspname = 'experiment'
    AND c.relname = 'test_result';
  oid  | schema_name |   relname   | relkind
-------+-------------+-------------+---------
 16425 | experiment  | test_result | r
(1 row)
```

---

### 5. Перевірка приведення `regclass` та безпечної функції `to_regclass`

```text
lab_measurements=>   SELECT 'experiment.test_result'::regclass;
        regclass
------------------------
 experiment.test_result
(1 row)

lab_measurements=>   SELECT to_regclass('experiment.test_result');
      to_regclass
------------------------
 experiment.test_result
(1 row)

lab_measurements=>   SELECT to_regclass('experiment.unknown_table');
 to_regclass
-------------

(1 row)
```
*(Повернення `NULL` замість помилки для неіснуючого об'єкта).*

---

### 6. Дослідження процесів сервера та робота двох паралельних сеансів

```text
-- Термінал 1:
lab_measurements=> SELECT pg_backend_pid();
 pg_backend_pid
----------------
           5063
(1 row)

-- Термінал 2:
lab_measurements=> SELECT pg_backend_pid();
 pg_backend_pid
----------------
           5874
(1 row)

-- Моніторинг активних процесів у базі:
lab_measurements=> SELECT pid, usename, datname, application_name, state
FROM pg_stat_activity
WHERE datname = 'lab_measurements'
ORDER BY pid;
 pid  |   usename   |     datname      | application_name | state
------+-------------+------------------+------------------+--------
 5063 | lab_student | lab_measurements | psql             | idle
 5874 | lab_student | lab_measurements | psql             | active
(2 rows)
```

---

### 7. Дослідження метакоманд `psql` та розширеного виводу

```text
lab_measurements=>   \set ECHO_HIDDEN on
lab_measurements=>   \dt experiment.*
/******** QUERY *********/
SELECT n.nspname as "Schema",
  c.relname as "Name",
  CASE c.relkind WHEN 'r' THEN 'table' WHEN 'v' THEN 'view' WHEN 'm' THEN 'materialized view' WHEN 'i' THEN 'index' WHEN 'S' THEN 'sequence' WHEN 't' THEN 'TOAST table' WHEN 'f' THEN 'foreign table' WHEN 'p' THEN 'partitioned table' WHEN 'I' THEN 'partitioned index' END as "Type",
  pg_catalog.pg_get_userbyid(c.relowner) as "Owner"
FROM pg_catalog.pg_class c
     LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
     LEFT JOIN pg_catalog.pg_am am ON am.oid = c.relam
WHERE c.relkind IN ('r','p','t','s','')
  AND n.nspname OPERATOR(pg_catalog.~) '^(experiment)$' COLLATE pg_catalog.default
ORDER BY 1,2;
/************************/

                 List of tables
   Schema   |    Name     | Type  |    Owner
------------+-------------+-------+-------------
 experiment | test_result | table | lab_student
(1 row)

lab_measurements=> SELECT * FROM pg_stat_activity WHERE pid = pg_backend_pid();
-[ RECORD 1 ]----+-------------------------------------------------------------
datid            | 16389
datname          | lab_measurements
pid              | 5874
leader_pid       |
usesysid         | 16388
usename          | lab_student
application_name | psql
client_addr      |
client_hostname  |
client_port      | -1
backend_start    | 2026-09-06 20:16:04.470233+03
xact_start       | 2026-09-06 20:18:38.877047+03
query_start      | 2026-09-06 20:18:38.877047+03
state_change     | 2026-09-06 20:18:38.877061+03
wait_event_type  |
wait_event       |
state            | active
backend_xid      |
backend_xmin     | 777
query_id         |
query            | SELECT * FROM pg_stat_activity WHERE pid = pg_backend_pid();
backend_type     | client backend

Time: 1.152 ms
```
