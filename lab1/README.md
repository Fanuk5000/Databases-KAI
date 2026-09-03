# PostgreSQL Lab 1: Database Architecture & System Catalogs

Лабораторна робота з дисципліни «Бази даних». Проєкт демонструє дворівневу організацію даних (`staging` та `core`), роботу з автоінкрементними і зовнішніми ключами, імпорт сирих даних через `\copy`, а також аналіз внутрішньої архітектури PostgreSQL через системні каталоги (`pg_database`, `pg_namespace`, `pg_class`) та `information_schema`.

---

## Структура проєкту

```text
postgres-lab1-architecture/
├── .gitignore
├── README.md
├── docker-compose.yml          # Швидкий старт оточення у Docker
├── data/
│   └── measurements.csv        # Вхідні тестові дані для імпорту
├── sql/
│   ├── 01_init_user_db.sql     # Створення ролі lab_student та бази lab_measurements
│   ├── 02_schema.sql           # Створення схем core/staging та таблиць
│   ├── 03_seed.sql             # Первинне наповнення (device, sensor)
│   ├── 04_import.sql           # Команда \copy для завантаження CSV
│   └── 05_queries.sql          # Перевірка системних каталогів та OID
└── docs/
    └── rage: postgres:16-alpineeport.md               # Детальний лабораторний звіт
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
# 1. Створення схем та таблиць
psql -U lab_student -d lab_measurements -f sql/02_schema.sql

# 2. Наповнення тестовими даними
psql -U lab_student -d lab_measurements -f sql/03_seed.sql

# 3. Імпорт CSV файлу
psql -U lab_student -d lab_measurements -f sql/04_import.sql

# 4. Виконання аналітичних запитів до системних каталогів
psql -U lab_student -d lab_measurements -f sql/05_queries.sql
```

---

## Протокол виконання та логи сесії (Execution Logs)

Нижче наведено верифіковані логи фактичного виконання операцій у СУБД PostgreSQL.

### 1. Інформація про поточну сесію та підключення

```text
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
 Backend PID          | 10691
 SSL Connection       | false
 Superuser            | off
 Hot Standby          | off
(12 rows)

 current_database | current_user 
------------------+--------------
 lab_measurements | lab_student
(1 row)

 server_version 
----------------
 18.6
(1 row)

 pg_backend_pid 
----------------
          10691
(1 row)
```

---

### 2. Стан баз даних та схем

```text
List of databases
       Name       |    Owner    | Encoding | Locale Provider |   Collate   |    Ctype    | Locale | ICU Rules |   Access privileges   
------------------+-------------+----------+-----------------+-------------+-------------+--------+-----------+-----------------------
 lab_measurements | lab_student | UTF8     | libc            | en_US.UTF-8 | en_US.UTF-8 |        |           | 
 postgres         | postgres    | UTF8     | libc            | en_US.UTF-8 | en_US.UTF-8 |        |           | 
 template0        | postgres    | UTF8     | libc            | en_US.UTF-8 | en_US.UTF-8 |        |           | =c/postgres          +
                  |             |          |                 |             |             |        |           | postgres=CTc/postgres
 template1        | postgres    | UTF8     | libc            | en_US.UTF-8 | en_US.UTF-8 |        |           | =c/postgres          +
                  |             |          |                 |             |             |        |           | postgres=CTc/postgres
(4 rows)

      List of schemas
  Name  |       Owner       
--------+-------------------
 public | pg_database_owner
(1 row)
```

---

### 3. Створені таблиці та детальна структура `core.sensor`

```text
lab_measurements=> \dt core.*
             List of tables
 Schema |  Name  | Type  |    Owner    
--------+--------+-------+-------------
 core   | device | table | lab_student
 core   | sensor | table | lab_student
(2 rows)

lab_measurements=> \dt staging.*
                 List of tables
 Schema  |      Name       | Type  |    Owner    
---------+-----------------+-------+-------------
 staging | raw_measurement | table | lab_student
(1 row)

lab_measurements=> \d core.sensor
                                    Table "core.sensor"
   Column    |          Type          | Collation | Nullable |           Default            
-------------+------------------------+-----------+----------+------------------------------
 sensor_id   | integer                |           | not null | generated always as identity
 device_id   | integer                |           | not null | 
 sensor_code | character varying(50)  |           | not null | 
 quantity    | character varying(100) |           | not null | 
 unit_symbol | character varying(20)  |           | not null | 
Indexes:
    "sensor_pkey" PRIMARY KEY, btree (sensor_id)
    "sensor_sensor_code_key" UNIQUE CONSTRAINT, btree (sensor_code)
Foreign-key constraints:
    "fk_sensor_device" FOREIGN KEY (device_id) REFERENCES core.device(device_id) ON DELETE CASCADE
```

---

### 4. Первинне наповнення (Seed Data)

```text
lab_measurements=> INSERT INTO core.device (device_name, model)
VALUES ('Redmi Note 9 pro', 'M2003J6B2G')
RETURNING device_id;
 device_id 
-----------
         1
(1 row)

INSERT 0 1

lab_measurements=> SELECT * FROM core.device; 
 device_id |   device_name    |   model    
-----------+------------------+------------
         1 | Redmi Note 9 pro | M2003J6B2G
(1 row)

lab_measurements=> SELECT * FROM core.sensor;
 sensor_id | device_id | sensor_code | quantity  | unit_symbol 
-----------+-----------+-------------+-----------+-------------
         1 |         1 | CPU_Mhz_001 | Frequence | Mhz
(1 row)
```

---

### 5. Опитування системних каталогів та OID

```text
lab_measurements=> SELECT oid, datname FROM pg_database;
  oid  |     datname      
-------+------------------
     5 | postgres
 16389 | lab_measurements
     1 | template1
     4 | template0
(4 rows)

lab_measurements=> SELECT
    n.nspname AS schema_name,
    c.relname AS table_name,
    c.oid AS table_oid,
    c.relkind AS object_type 
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('core', 'staging')
  AND c.relkind = 'r';
 schema_name |   table_name    | table_oid | object_type 
-------------+-----------------+-----------+-------------
 core        | device          |     16393 | r
 core        | sensor          |     16401 | r
 staging     | raw_measurement |     16418 | r
(3 rows)
```

---

### 6. Порівняння метаданих: `information_schema.columns` проти `\d`

```text
lab_measurements=> SELECT                                                                
        table_schema,                                                              
        table_name,                                                                
        column_name,                                                               
        ordinal_position,                                                          
        data_type,                                                                 
        is_nullable                                                                
    FROM information_schema.columns                                                
    WHERE table_schema = 'core'                                                    
      AND table_name = 'sensor'                                                    
    ORDER BY ordinal_position;
 table_schema | table_name | column_name | ordinal_position |     data_type     | is_nullable 
--------------+------------+-------------+------------------+-------------------+-------------
 core         | sensor     | sensor_id   |                1 | integer           | NO
 core         | sensor     | device_id   |                2 | integer           | NO
 core         | sensor     | sensor_code |                3 | character varying | NO
 core         | sensor     | quantity    |                4 | character varying | NO
 core         | sensor     | unit_symbol |                5 | character varying | NO
(5 rows)
```

---

### 7. Імпорт CSV та перевірка кількості записів

```text
lab_measurements=> SELECT COUNT(*) FROM staging.raw_measurement;
 count 
-------
     4
(1 row)

lab_measurements=> SELECT * FROM staging.raw_measurement;
 sensor_code |     measured_at     |                   value_text                    
-------------+---------------------+-------------------------------------------------
 CPU_Mhz_001 | 2026-09-03 10:00:00 | 22.5                                           
 CPU_Mhz_001 | 2026-09-03 10:05:00 | 22.7                                           
 CPU_Mhz_001 | 2026-09-03 10:10:00 | 23.1                                           
 CPU_Mhz_001 | 2026-09-03 10:15:00 | 22.9
(4 rows)
```
