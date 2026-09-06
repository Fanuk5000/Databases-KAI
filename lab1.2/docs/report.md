# Лабораторна робота № 1.2: Дослідження підключень, схем і системних каталогів PostgreSQL

**Дисципліна:** Бази даних  
**Користувач БД:** `lab_student`  
**База даних:** `lab_measurements`  
**Версія PostgreSQL:** 18.6  
**Операційне середовище:** Linux, клієнт `psql` (Protocol Version 3.0, Unix Socket)

---

## 1. Мета роботи

1. Дослідити поточне клієнт-серверне підключення до СУБД PostgreSQL, параметри з'єднання та конфігурацію шляху пошуку схем (`search_path`).
2. Опанувати роботу з просторами імен (схемами), створити ізольовану схему `experiment` та реляційну таблицю з автоінкрементним стовпцем (`GENERATED ALWAYS AS IDENTITY`).
3. Дослідити вплив механізму розв'язання імен (`search_path`) на виконання SQL-запитів та обґрунтувати переваги використання повних імен об'єктів.
4. Зіставити методи отримання метаданих через стандартизоване представлення `information_schema.columns` та спеціалізовану метакоманду клієнта `psql` (`\d`).
5. Провести низькорівневу інспекцію об'єктів через внутрішні системні каталоги `pg_catalog` (`pg_class`, `pg_namespace`), ідентифікувати `OID` та атрибут `relkind`.
6. Дослідити поведінку псевдотипу `regclass` та безпечної системної функції `to_regclass()` для існуючих і неіснуючих об'єктів.
7. Дослідити мультипроцесну модель обслуговування підключень PostgreSQL шляхом ідентифікації системних `PID` для кількох паралельних сеансів у динамічному поданні `pg_stat_activity`.
8. Дослідити внутрішню механіку роботи метакоманд утиліти `psql` через активацію режиму `\set ECHO_HIDDEN on`, а також застосувати розширений вивід (`\x auto`) та вимірювання часу виконання запитів (`\timing on`).

---

## 2. Теоретичні відомості та архітектурний аналіз

### 2.1. Мультипроцесна архітектура сервера PostgreSQL
На відміну від багатьох інших реляційних СУБД (наприклад, MySQL або MS SQL Server, де нові сесії створюються у вигляді легких потоків — *threads*), PostgreSQL базується на **мультипроцесній моделі (process-based)**.

```text
               +----------------------------------+
               |   Головний процес (Postmaster)   |
               |        Слухає порт 5432          |
               +-----------------+----------------+
                                 | fork()
         +-----------------------+-----------------------+
         |                                               |
+--------v--------+                             +--------v--------+
| Backend Process |                             | Backend Process |
|    PID: 5063    |                             |    PID: 5874    |
|   (Сеанс 1)     |                             |   (Сеанс 2)     |
+--------^--------+                             +--------^--------+
         | Unix Domain Socket                            | Unix Domain Socket
+--------+--------+                             +--------+--------+
|  Клієнт psql 1  |                             |  Клієнт psql 2  |
|  (Термінал 1)   |                             |  (Термінал 2)   |
+-----------------+                             +-----------------+
```

- Коли клієнт ініціює підключення, головний процес-диспетчер (`postmaster`) створює через системний виклик `fork()` окремий серверний процес — **backend worker process**.
- Кожен такий процес має власний унікальний ідентифікатор у системі (**PID**), власну виділену віртуальну пам'ять для сортування та хешування (`work_mem`), але водночас має доступ до загальної пам'яті сервера (**Shared Memory**: буферний пул `shared_buffers`, журнал випереджального запису `WAL buffers`, блокування `lock table`).
- **Перевага моделі:** Ізоляція збоїв. Якщо один клієнтський бекенд аварійно завершить роботу через критичну помилку пам'яті, інші клієнтські сесії залишаться ізольованими та захищеними.

### 2.2. Ієрархія сутностей та механізм `search_path`
Ієрархія збереження даних у PostgreSQL має чотири рівні:
$$\text{Екземпляр (Instance)} \longrightarrow \text{База даних (Database)} \longrightarrow \text{Схема (Schema)} \longrightarrow \text{Об'єкт (Table, View, Index)}$$

Схема є логічним простором імен усередині бази даних. Якщо під час звернення до таблиці схема не вказана явно, СУБД звертається до змінної середовища сесії `search_path`, яка містить перелік схем у порядку пріоритету перегляду:
- За замовчуванням: `"$user", public`.
- Якщо перша знайдена схема містить об'єкт з таким ім'ям, запит виконується до неї.
- Якщо таблиця розташована в іншій схемі, якої немає в списку або яка має нижчий пріоритет, сервер повертає помилку `relation does not exist`.

---

## 3. Протокол виконання та аналіз фактичних логів сесії

Усі наведені нижче результати відповідають фактичному протоколу виконання з файлу `savings.txt`.

### 3.1. Перевірка з'єднання та параметрів середовища

Виконано перевірку поточного контексту сеансу:

```text
lab_measurements=> SELECT current_database(), current_user, current_schema();
 current_database | current_user | current_schema
------------------+--------------+----------------
 lab_measurements | lab_student  | public
(1 row)
```

Перевірка детальних атрибутів підключення утилітою `\conninfo`:
```text
lab_measurements=> \conninfo
           Connection Information
      Parameter       |        Value
----------------------+---------------------
 Database             | lab_measurements
 Client User          | lab_student
 Socket Directory     | /var/run/postgresql
 Server Port          | 5432
 Protocol Version     | 3.0
 Password Used        | false
 GSSAPI Authenticated | false
 Backend PID          | 8913
 SSL Connection       | false
 Superuser            | off
 Hot Standby          | off
(12 rows)
```

Фіксація версії сервера та початкового шляху пошуку:
```text
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

Огляд наявних баз даних (`\l`) та схем (`\dn`):
```text
lab_measurements-> \dn
       List of schemas
  Name   |       Owner
---------+-------------------
 core    | lab_student
 public  | pg_database_owner
 staging | lab_student
(3 rows)
```
*Аналіз:* На старті в базі присутні схеми `core`, `staging` (створені в попередній роботі) та системна `public`. Схеми `experiment` ще немає.

---

### 3.2. Створення схеми `experiment`, таблиці та вставка даних

Створено схему `experiment` та перевірено її наявність:
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
```

Створено таблицю `experiment.test_result` та перевірено її реєстрацію:
```text
lab_measurements=> \dt experiment.*
                 List of tables
   Schema   |    Name     | Type  |    Owner
------------+-------------+-------+-------------
 experiment | test_result | table | lab_student
(1 row)
```

Структура таблиці згідно з клієнтською карткою `\d`:
```text
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
```

Додано 3 тестові виміри та перевірено вміст:
```text
lab_measurements=> SELECT * FROM experiment.test_result;
 result_id | experiment_name | measured_value | unit_symbol
-----------+-----------------+----------------+-------------
         1 | Voltage test    |           12.4 | V
         2 | Current test    |            1.8 | A
         3 | Speed test      |           1480 | rpm
(3 rows)
```

---

### 3.3. Експерименти з простором імен та `search_path`

При спробі звернутися до таблиці без префіксу схеми:
```text
lab_measurements=> SHOW search_path;
   search_path
-----------------
 "$user", public
(1 row)

lab_measurements=> SELECT * FROM test_result;
ERROR:  relation "test_result" does not exist
LINE 1: SELECT * FROM test_result;
```
*Причина помилки:* Поточний шлях пошуку містить лише схему користувача (якої не існує) та `public`. Оскільки таблиця створена в схемі `experiment`, сервер її не знаходить.

Встановлення схеми `experiment` у початок `search_path`:
```text
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

#### Чому `SELECT * FROM experiment.test_result;` є більш однозначною, ніж `SELECT * FROM test_result;`?
1. **Детермінованість (Однозначність):** Якщо інший користувач або адміністратор створить таблицю з назвою `test_result` у схемі `public`, і в `search_path` схема `public` виявиться попереду `experiment`, некваліфікований запит почне зчитувати чужу таблицю. Повна кваліфікація (`schema.table`) жорстко прив'язує запит до цільового простору імен.
2. **Безпека (Search Path Hijacking):** Вразливість підміни об'єктів виникає, коли зловмисник розміщує шкідливий об'єкт або функцію у схемі, що переглядається раніше. Використання повністю кваліфікованих імен унеможливлює подібні атаки.
3. **Стійкість коду:** Запит не ламається при зміні користувацьких або глобальних конфігурацій `search_path`.

---

### 3.4. Інтроспекція метаданих: `information_schema` проти `\d`

Отримано перелік стовпців через стандартне ANSI-представлення:
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
```

Порівняння двох підходів до перегляду структури:

| Критерій | `information_schema.columns` | Метакоманда `\d experiment.test_result` |
| :--- | :--- | :--- |
| **Стандарт / Рівень** | Міжнародний стандарт ANSI/ISO SQL. Підтримується в PostgreSQL, MySQL, MariaDB, MS SQL Server. | Власна вбудована службова команда клієнта `psql`. |
| **Призначення** | Програмне зчитування метаданих (скрипти, міграції, ORM, ETL-процеси). | Інтерактивна робота адміністратора чи розробника в терміналі. |
| **Формат даних** | Табличний реляційний набір рядків. Зручно фільтрувати через `WHERE` та сортувати. | Форматована текстова картка об'єкта. |
| **Комплексність відображення** | Містить виключно дані про колонки. Інформація про індекси, обмеження та тригери вимагає додаткових JOIN із суміжними в'юхами (`table_constraints`, `key_column_usage`). | Одразу комплексно агрегує: перелік колонок, типи, дефолтні генератори (`identity`), первинні ключі (`PRIMARY KEY, btree`), зовнішні ключі та посилання. |

---

### 3.5. Низькорівневе опитування каталогів `pg_catalog` та OID

Виконано прямий SQL-запит до базових системних таблиць `pg_class` (реляційні об'єкти) та `pg_namespace` (схеми):
```text
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

- **`oid = 16425`**: Системний числовий ідентифікатор таблиці `test_result` у даній базі даних.
- **`schema_name = experiment`**: Назва простору імен, визначена через зв'язок `c.relnamespace = n.oid`.
- **`relkind = 'r'`**: Тип об'єкта. У каталозі `pg_class` значення `'r'` позначає звичайну таблицю (*ordinary relation / table*).

---

### 3.6. Дослідження псевдотипу `regclass` та функції `to_regclass()`

Виконано перетворення текстових імен в ідентифікатори:
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
```

Перевірка неіснуючої таблиці:
```text
lab_measurements=>   SELECT to_regclass('experiment.unknown_table');
 to_regclass
-------------

(1 row)
```

#### Що повертає `to_regclass()`, якщо об'єкт не існує?
Функція `to_regclass()` при відсутності об'єкта повертає значення **`NULL`**.  
*Важливість:* На відміну від прямого приведення `'not_exists'::regclass`, яке негайно перериває виконання транзакції з фатальною помилкою `ERROR: relation "..." does not exist`, функція `to_regclass()` безпечно повертає `NULL`. Це дає змогу будувати надійні ідемпотентні скрипти перевірки існування таблиць перед виконанням DDL:
```sql
IF to_regclass('my_schema.my_table') IS NOT NULL THEN ...
```

---

### 3.7. Дослідження процесів сервера та робота двох паралельних сеансів

Перевірка PID першого сеансу:
```text
lab_measurements=>   SELECT pg_backend_pid();
 pg_backend_pid
----------------
           5063
(1 row)

lab_measurements=>   SELECT
      pid,
      usename,
      datname,
      application_name,
      backend_type,
      state
  FROM pg_stat_activity
  WHERE pid = pg_backend_pid();
 pid  |   usename   |     datname      | application_name |  backend_type  | state
------+-------------+------------------+------------------+----------------+--------
 5063 | lab_student | lab_measurements | psql             | client backend | active
(1 row)
```

Відкрито **друге вікно термінала** та виконано паралельне підключення тим самим користувачем `lab_student`:
- **PID сеансу 1 (Термінал 1):** `5063`
- **PID сеансу 2 (Термінал 2):** `5874`

Опитування таблиці `pg_stat_activity` з фіксацією обох сесій:
```text
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

#### Чому два підключення одного й того самого користувача мають різні PID?
PostgreSQL реалізує модель «окремий процес на кожне підключення» (*one process per connection*). При кожному запиті на встановлення TCP або Unix-сокет з'єднання демон `postgres` здійснює виклик `fork()` і породжує окремий повноцінний процес операційної системи.  
Навіть якщо ім'я користувача (`lab_student`), пароль, хост і цільова база даних ідентичні, кожен сеанс отримує власний незалежний контекст виконання, власні змінні сесії (наприклад, незалежні `search_path`), окремий лічильник транзакцій та свій унікальний **PID** для повної апаратної ізоляції адресного простору пам'яті.

---

### 3.8. Дослідження метакоманд через `\set ECHO_HIDDEN on`, `\x` та `\timing`

Увімкнено режим трасування запитів клієнта:
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
```

#### Висновки щодо метакоманд:
1. **Чи є `\dt` звичайною SQL-командою?**  
   Ні. `\dt` — це внутрішня макрокоманда клієнтського інтерфейсу `psql`. Сервер СУБД нічого не знає про команду `\dt`.
2. **Звідки `psql` отримує інформацію про таблиці?**  
   Клієнт `psql` автоматично формує розгорнутий SQL-запит до системного каталогу ядра PostgreSQL — `pg_catalog.pg_class`, об'єднуючи його з каталогом просторів імен `pg_catalog.pg_namespace` та перевіряючи тип об'єкта `c.relkind`.

Перевірка роботи розширеного вертикального відображення (`\x auto`) та вимірювання часу (`\timing on`):
```text
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
- Режим `\x auto` розгортає 1 широкий рядок з 20+ стовпцями у зручний вертикальний список ключ-значення (`-[ RECORD 1 ]-`).
- Опція `\timing on` зафіксувала час виконання запиту: **`1.152 ms`**.

---

## 4. Відповіді на контрольні питання

### 1. Що таке клієнт у PostgreSQL?
**Відповідь:** Клієнт — це будь-яка зовнішня програма або бібліотека, яка встановлює мережеве з'єднання (TCP/IP або Unix Domain Socket) із сервером PostgreSQL за протоколом Frontend/Backend Protocol 3.0 та передає SQL-команди для виконання. Приклади: утиліта `psql`, графічні клієнти `pgAdmin` / `DBeaver`, додатки на Python (`psycopg2`, `asyncpg`), Go, Java тощо.

### 2. Що таке сервер PostgreSQL?
**Відповідь:** Сервер PostgreSQL — це комплекс системних процесів ядра СУБД (на чолі з процесом-супервізором `postgres`/`postmaster`), що керує фізичними файлами даних, кешем у спільній пам'яті (`shared_buffers`), транзакційним журналом (`WAL`), плануванням і виконанням запитів, а також забезпечує дотримання вимог ACID.

### 3. Чим база даних відрізняється від схеми?
**Відповідь:** 
- **База даних (`Database`):** Є найвищою межею логічної та фізичної ізоляції в межах екземпляра. Таблиці з різних баз даних не можна з'єднати в одному стандартному SQL-запиті (без спеціальних розширень `dblink` або `postgres_fdw`).
- **Схема (`Schema`):** Це логічний простір імен *всередині* однієї бази даних. Різні схеми можуть містити однойменні таблиці, і до них можна звертатися в межах одного запиту та єдиної транзакції (наприклад, `JOIN core.device ON ... JOIN staging.raw ...`).

### 4. Для чого використовується `search_path`?
**Відповідь:** `search_path` визначає впорядкований список схем, за якими сервер автоматично шукає об'єкти (таблиці, в'юхи, функції), якщо в SQL-запиті їхнє ім'я вказано без префіксу схеми (без явної кваліфікації).

### 5. Для чого використовується команда `\conninfo`?
**Відповідь:** Клієнтська команда утиліти `psql`, яка виводить повну службову інформацію про активне підключення: ім'я бази даних, користувача, тип сокета або IP-хост, порт, версію протоколу, стан шифрування (SSL) та PID бекенд-процесу.

### 6. Що показує команда `\dn`?
**Відповідь:** Виводить список усіх зареєстрованих схем (namespaces) поточної бази даних разом з інформацією про їхніх власників (`Owner`).

### 7. Що показує команда `\dt`?
**Відповідь:** Виводить список реляційних таблиць (`relkind = 'r'`) у схемах, доступних згідно з поточним `search_path` або заданим шаблоном (наприклад, `\dt experiment.*`).

### 8. Для чого використовується команда `\d`?
**Відповідь:** Для детальної інспекції структури конкретного об'єкта (таблиці, індексу, представлення). Вона відображає перелік усіх колонок, їхні типи даних, модифікатори `NULL`/`NOT NULL`, значення за замовчуванням / правила `IDENTITY`, індекси та зовнішні ключі.

### 9. Що таке `information_schema`?
**Відповідь:** Це набір стандартних представлень (views), визначених стандартом ANSI/ISO SQL. Вони надають уніфікований доступ до метаданих бази даних, що дозволяє писати крос-платформний код для інспекції структур даних незалежно від конкретної СУБД.

### 10. Що таке `pg_catalog`?
**Відповідь:** Це власна системна схема PostgreSQL, де розміщені базові таблиці ядра рушія СУБД (`pg_class`, `pg_namespace`, `pg_type`, `pg_attribute` тощо). Усі об'єкти бази даних безпосередньо реєструються та описуються в `pg_catalog`.

### 11. Що таке `OID`?
**Відповідь:** `OID` (Object Identifier) — внутрішній системний 32-бітний беззнаковий числовий ідентифікатор, який призначається сутностям у каталогах PostgreSQL (таблицям, типам даних, базам даних, функціям тощо) для внутрішньої лінковки між системними таблицями.

### 12. Що означає `relkind = 'r'`?
**Відповідь:** В атрибуті `relkind` системного каталогу `pg_class` символ `'r'` позначає звичайну таблицю (*ordinary table / relation*). Інші значення: `'v'` — view, `'m'` — materialized view, `'i'` — index, `'S'` — sequence, `'p'` — partitioned table.

### 13. Для чого використовується `to_regclass()`?
**Відповідь:** Для безпечного перетворення текстової назви відношення (наприклад, `'experiment.test_result'`) у відповідний OID або тип `regclass`. Якщо об'єкт не існує, функція повертає `NULL` без викидання критичної помилки, що робить її незамінною для перевірок у процедурних скриптах.

### 14. Що повертає `pg_backend_pid()`?
**Відповідь:** Повертає системний ідентифікатор процесу операційної системи (`Process ID`), під яким на сервері виконується поточний `backend worker process`, закріплений за поточною клієнтською сесією.

### 15. Чому два окремі підключення мають різні PID?
**Відповідь:** Через мультипроцесну архітектуру PostgreSQL. Для кожного клієнтського підключення операційна система створює окремий ізольований процес `postgres` через системний виклик `fork()`. Кожен процес має власний виділений `PID` та власну ізольовану область пам'яті.

### 16. Для чого використовується `pg_stat_activity`?
**Відповідь:** Це динамічне системне представлення моніторингу реального часу. Воно показує поточний стан усіх сеансів: активні чи очікують (`state`), текст виконуваного запиту (`query`), час старту сесії та транзакції, тип очікування блокувань (`wait_event`).

### 17. Чи є `\dt` SQL-командою?
**Відповідь:** Ні. Команда `\dt` — це внутрішня макрокоманда інтерфейсу клієнта `psql`. Вона перехоплюється утилітою `psql`, транслюється у внутрішній SQL-запит до каталогу `pg_catalog.pg_class` і надсилається серверу як звичайний `SELECT`.

### 18. Для чого використовується `\x auto`?
**Відповідь:** Вмикає режим автоперемикання формату виводу: якщо ширина рядків таблиці з результатами перевищує поточну ширину вікна термінала, `psql` автоматично перемикається з горизонтального відображення колонок на вертикальне відображення записів (картками).

### 19. Для чого використовується `\timing on`?
**Відповідь:** Вмикає вбудований секундомір на боці клієнта `psql`, який після виконання кожного SQL-запиту вимірює та виводить час його виконання сервером у мілісекундах (наприклад, `Time: 1.152 ms`).

---

## 5. Висновки

1. **Досліджено підключення та середовище сеансу:** За допомогою `\conninfo`, системних функцій та каталогів з'ясовано параметри поточного підключення (база `lab_measurements`, користувач `lab_student`, сокет `/var/run/postgresql`, порт 5432, версія 18.6).
2. **Опановано керування схемами та шляхом пошуку:** Створено нову ізольовану схему `experiment` та таблицю `test_result` із автоінкрементним стовпцем типу `bigint GENERATED ALWAYS AS IDENTITY`. На практиці підтверджено виникнення помилки `relation does not exist` через відсутність схеми в `search_path` та обґрунтовано безпеку використання повних імен виду `schema.table`.
3. **Проведено порівняльний аналіз системних метаданих:** Порівняно представлення стандарту ANSI SQL (`information_schema.columns`) та клієнтську команду `\d`. З'ясовано, що `information_schema` є переносимим інструментом для програмного аналізу, а `\d` — комплексною консольною утилітою для людини.
4. **Досліджено каталоги ядра СУБД та OID:** Виконано прямий SQL-запит до `pg_catalog.pg_class` та `pg_catalog.pg_namespace`, зафіксовано OID таблиці `16425` та підтверджено тип реляційного об'єкта `relkind = 'r'`.
5. **Проаналізовано поведінку функцій ідентифікації:** Експериментально доведено, що функція `to_regclass()` при зверненні до неіснуючого об'єкта повертає `NULL`, не перериваючи виконання транзакції.
6. **Підтверджено мультипроцесну архітектуру PostgreSQL:** Через паралельний запуск двох клієнтських терміналів та аналіз динамічного каталогу `pg_stat_activity` зафіксовано різні ідентифікатори процесів (`PID = 5063` та `PID = 5874`) для одного й того ж користувача `lab_student`, що підтверджує модель повної ізоляції клієнтських процесів ОС.
7. **Розкрито механізм роботи метакоманд `psql`:** Через режим `\set ECHO_HIDDEN on` наочно продемонстровано, що клієнтські команди на зразок `\dt` не є частиною SQL-синтаксису сервера, а є клієнтськими макросами, які транслюються в запити до `pg_catalog`. Застосовано розширене форматування `\x auto` та зафіксовано час виконання запиту `1.152 ms` за допомогою `\timing on`.
