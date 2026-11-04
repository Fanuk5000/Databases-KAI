# Лабораторна робота № 9: Індексні методи, EXPLAIN та оптимізація запитів у PostgreSQL

**Дисципліна:** Бази даних  
**Користувач БД:** `postgres`  
**База даних:** `postgres`  
**Схема БД:** `lab09_pr`  
**Інфраструктура:** Хмарний кластер Supabase (PostgreSQL 17.11)  
**Клієнтське середовище:** Нативний термінальний сеанс CLI `psql` в ОС Linux (`PID 107561`)  
**Журнал первинних логів:** [savings.txt](file:///home/mafi2/Projects/DataBase-discipline/lab9/savings.txt)  

---

## 1. Мета роботи

1. **Опанування інструментів профілювання запитів:** Навчитися аналізувати плани виконання SQL-запитів за допомогою системної інструкції `EXPLAIN (ANALYZE, BUFFERS)` та розуміти різницю між теоретичною вартістю планувальника (`cost`) і фактичними показниками виконання (`actual time`, `actual rows`, `shared hit/read`).
2. **Практичне дослідження індексних структур у PostgreSQL:** Вивчити механіку та особливості застосування класичних збалансованих дерев (B-tree), інвертованих індексів (GIN) та блокових діапазонних індексів (BRIN).
3. **Освоєння оптимізаційних стратегій індексації:** Експериментально дослідити переваги складених індексів (Composite Index), часткових індексів (Partial Index) та покривних індексів (Covering Index через фразу `INCLUDE`).
4. **Порівняльний аналіз вузлів доступу до даних (Scan Methods):** Дослідити поведінку вузлів `Seq Scan`, `Index Scan`, `Bitmap Index Scan`, `Bitmap Heap Scan` та `Index Only Scan` з нульовим зверненням до сторінок таблиці (`Heap Fetches: 0`).
5. **Оцінка ефективності індексів:** Порівняти час виконання запитів, кількість зчитаних 8-кілобайтних блоків пам'яті (`shared hit/read`) та дисковий простір, зайнятий таблицями й індексами.
6. **Аналіз алгоритмів з'єднання таблиць (JOIN):** Дослідити роботу з'єднань (`Hash Join`, `Nested Loop`, `Merge Join`) при вибірці даних із зовнішніми ключами.
7. **З'ясування граничних умов роботи оптимізатора:** Визначити фактори, за яких вартісний планувальник PostgreSQL ігнорує наявний індекс на користь повного послідовного сканування (`Seq Scan`).
8. **Дотримання інженерних стандартів ізоляції схеми:** Забезпечити сувору пряму двокомпонентну кваліфікацію об'єктів схеми `lab09_pr.` без застосування небезпечної практики мутації параметра `search_path`.

---

## 2. Теоретичні відомості та архітектурний аналіз

### 2.1. Концепція індексації в реляційних СУБД та ціна індексів

Індекс — це спеціалізована фізична структура даних, яка логічно пов'язана з таблицею і призначена для прискорення пошуку, фільтрації та сортування кортежів за значеннями одного чи кількох стовпців. Замість повного послідовного перегляду всіх сторінок таблиці від початку до кінця СУБД звертається до компактного індексного дерева або списку посилань, звідки миттєво отримує фізичні покажчики `ctid` (номер блоку, зміщення в блоці) на цільові рядки.

**Ціна індексації (Engineering Trade-offs):**
- **Додатковий дисковий простір:** Кожен індекс зберігається в окремому файлі на диску та конкурує з таблицями за місце в буферному пулі оперативної пам'яті (`shared_buffers`).
- **Накладні витрати на модифікацію (Write Amplification):** При кожній операції `INSERT`, `DELETE` або `UPDATE` (якщо змінюється індексований стовпець або відсутня оптимізація HOT — Heap-Only Tuples) PostgreSQL зобов'язаний синхронно вносити зміни в усі пов'язані індекси, що збільшує обсяг запису у WAL та сповільнює транзакції запису.

---

### 2.2. Класифікація та архітектура індексних методів доступу

PostgreSQL надає потужний набір вбудованих методів доступу (Access Methods):

1. **B-tree (Balanced Tree):**
   - Метод за замовчуванням. Реалізує самозбалансоване дерево високої розгалуженості (high fan-out).
   - Підтримує відсортований порядок ключів.
   - Ефективний для операторів `=`, `<`, `<=`, `>`, `>=`, `BETWEEN`, `IN`, сортування `ORDER BY` та префіксного пошуку `LIKE 'abc%'`.
2. **Hash:**
   - Будує 32-бітну хеш-таблицю.
   - Підтримує виключно перевірку на точну рівність (`=`).
   - Не підтримує діапазонні запити та сортування. Починаючи з версії 10, підтримує журналювання у WAL.
3. **GiST (Generalized Search Tree):**
   - Узагальнене дерево пошуку для складних багатовимірних об'єктів: геометричні фігури (PostGIS), часові інтервали (`tsrange`), повнотекстовий пошук, оператори пошуку найближчих сусідів (`<->`) та обмеження виключення (`EXCLUDE`).
4. **SP-GiST (Space-Partitioned GiST):**
   - Реалізує незбалансовані дерева просторового розбиття (quad-tree, k-d tree, префіксні radix-дерева).
   - Оптимальний для нерівномірно розподілених даних (IP-адреси `inet`, телефонні номери, координати точок).
5. **GIN (Generalized Inverted Index):**
   - Інвертований індекс для складених і колекційних типів (масиви `text[]`, документи `jsonb`, лексеми `tsvector`).
   - Розбиває складні значення на окремі елементи та пов'язує кожен унікальний елемент із відсортованим списком рядків (`posting list` або `posting tree`), де цей елемент зустрічається.
   - Забезпечує блискавичну перевірку входження (`@>`, `?`, `@@`).
6. **BRIN (Block Range Index):**
   - Зберігає метадані (мінімум і максимум) для послідовних діапазонів сторінок таблиці (за замовчуванням 128 блоків, у лабораторній роботі налаштовано на 32 блоки).
   - Займає в сотні разів менше дискового простору, ніж B-tree.
   - Ідеальний для велетенських аналітичних таблиць, де фізичний порядок рядків строго корелює зі значеннями стовпця (послідовні часові ряди, покази лічильників).

---

### 2.3. Спеціалізовані стратегії побудови індексів

- **Unique Index:** Забезпечує унікальність значень стовпця; генерується автоматично при створенні `PRIMARY KEY` або `UNIQUE`.
- **Composite Index (Складений індекс):** Індекс за кількома стовпцями `(col1, col2)`. Ефективність залежить від порядку стовпців: спочатку повинні йти стовпці з умовою точної рівності (`=`), а потім — стовпці з діапазонами (`<`, `>`, `BETWEEN`) або сортуванням.
- **Partial Index (Частковий індекс):** Створюється з виразом `WHERE condition` і містить посилання лише на ті рядки, що задовольняють фільтр. Дозволяє виключити індексацію 99% регулярних рядків та тримати індекс ультракомпактним для рідкісних аномалій (`WHERE NOT is_valid`).
- **Expression Index (Індекс за виразом):** Будується за результатом функції (наприклад, `lower(email)`), уможливлюючи індексний пошук без модифікації вихідних даних таблиці.
- **Covering Index (Покривний індекс через `INCLUDE`):** Додає допоміжні стовпці у листові сторінки B-tree (`CREATE INDEX ... (key_col) INCLUDE (payload_col)`). Це дозволяє СУБД виконати **Index Only Scan**, оскільки всі необхідні поля вибираються прямо з індексу без звернення до фізичних сторінок таблиці.

---

### 2.4. Інструментарій аналізу планів виконання: `EXPLAIN`, `ANALYZE`, `BUFFERS`

- **`EXPLAIN`:** Показує дерево вузлів плану, розрахованих оптимізатором, та очікувану вартість (`cost=start_cost..total_cost rows=... width=...`) без запуску запиту.
- **`EXPLAIN ANALYZE`:** Виконує запит, заміряє фактичний час виконання кожного вузла (`actual time=start..total ms`) та кількість реально повернутих рядків (`rows=... loops=...`).
- **`BUFFERS`:** Показує взаємодію з буферним пулом оперативної пам'яті:
  - `shared hit`: блок знайдено в оперативній пам'яті (`shared_buffers`);
  - `shared read`: блок зчитано з дискового накопичувача/кешу ОС;
  - `dirtied`: кількість сторінок, модифікованих під час виконання.

#### Основні типи вузлів сканування (Scan Methods)
- **`Seq Scan` (Sequential Scan):** Повне послідовне сканування всіх блоків таблиці.
- **`Index Scan`:** Пошук через B-tree із безпосереднім вичитуванням знайдених кортежів зі сторінок таблиці (ефективно для вибірки одиничних рядків).
- **`Bitmap Index Scan` + `Bitmap Heap Scan`:** Індекс формує бітову карту сторінок таблиці з потрібними рядками (`Bitmap Index Scan`), а `Bitmap Heap Scan` впорядковано зчитує ці сторінки, зменшуючи випадковий доступ до диска, та виконує контроль умов (`Recheck Cond`).
- **`Index Only Scan`:** Запит обслуговується виключно сторінками індексу без звернення до таблиці (за умови підтвердження видимості через Visibility Map, `Heap Fetches: 0`).

---

## 3. Протокол виконання та детальний аналіз результатів експериментів

Усі вимірювання проведено на хмарному кластері **Supabase (PostgreSQL 17.11)** через нативний сеанс CLI `psql` (PID бекенду `107561`). Логи команд і планів збережено у файлі [savings.txt](file:///home/mafi2/Projects/DataBase-discipline/lab9/savings.txt).

---

### 3.1. Перевірка середовища сесії та скидання схеми `lab09_pr`

```sql
SELECT current_database(), current_user, pg_backend_pid(), current_setting('server_version');
SHOW search_path;
DROP SCHEMA IF EXISTS lab09_pr CASCADE;
CREATE SCHEMA lab09_pr;
```

**Фактичний результат з логу:**
```text
 current_database | current_user | pg_backend_pid | current_setting 
------------------+--------------+----------------+-----------------
 postgres         | postgres     |         107561 | 17.11
(1 row)

         search_path          
------------------------------
 "$user", public, extensions
(1 row)

DROP SCHEMA
CREATE SCHEMA
```

**Аналіз:** Підтверджено версію сервера `17.11`, унікальний PID `107561`. Параметр `search_path` залишається стандартним системним; усі звернення виконуються з явною схемою `lab09_pr.`.

---

### 3.2. Створення об'єктів та наповнення даними

Створення таблиць довідника сенсорів і вимірювань:
```sql
CREATE TABLE lab09_pr.sensors (
    id integer PRIMARY KEY,
    sensor_code text NOT NULL UNIQUE,
    location text NOT NULL
);

CREATE TABLE lab09_pr.readings (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sensor_id integer NOT NULL REFERENCES lab09_pr.sensors(id),
    measured_at timestamptz NOT NULL,
    temperature numeric(5,2) NOT NULL,
    is_valid boolean NOT NULL,
    tags text[] NOT NULL
);
```

Генерація 100 датчиків та 100 000 вимірювань:
```sql
INSERT INTO lab09_pr.sensors (id, sensor_code, location)
SELECT n, 'SNS-' || lpad(n::text, 3, '0'), 'Сектор ' || (((n - 1) / 20) + 1)
FROM generate_series(1, 100) AS g(n);

INSERT INTO lab09_pr.readings (sensor_id, measured_at, temperature, is_valid, tags)
SELECT 
    ((n - 1) % 100) + 1,
    TIMESTAMPTZ '2026-01-01 00:00+00' + (n - 1) * INTERVAL '1 minute',
    18.0 + (n % 220)::numeric / 10,
    n % 500 <> 0,
    CASE WHEN n % 500 = 0 THEN ARRAY['alarm']::text[] ELSE ARRAY['normal']::text[] END
FROM generate_series(1, 100000) AS g(n);

ANALYZE lab09_pr.sensors;
ANALYZE lab09_pr.readings;
```

Верифікація наповнення:
```sql
SELECT
    COUNT(*) AS total_readings,
    COUNT(*) FILTER (WHERE NOT is_valid) AS invalid_readings,
    COUNT(*) FILTER (WHERE tags @> ARRAY['alarm']::text[]) AS alarms
FROM lab09_pr.readings;
```

**Результат:**
```text
 total_readings | invalid_readings | alarms 
----------------+------------------+--------
         100000 |              200 |    200
(1 row)
```

Таблицю успішно наповнено 100 000 записами з кроком в 1 хвилину. Рівно 200 записів позначено як невалідні з тегом `alarm`.

---

### 3.3. Дослід 1. Базовий пошук за діапазоном без індексу (Baseline Seq Scan)

Завдання: знайти 60 записів за 1 годину (з 12:00 до 13:00 02.01.2026).
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, sensor_id, temperature
FROM lab09_pr.readings
WHERE measured_at >= TIMESTAMPTZ '2026-01-02 12:00+00'
  AND measured_at <  TIMESTAMPTZ '2026-01-02 13:00+00';
```

**Фактичний план виконання з логу [savings.txt](file:///home/mafi2/Projects/DataBase-discipline/lab9/savings.txt):**
```text
Seq Scan on readings  (cost=0.00..2720.00 rows=56 width=18) (actual time=0.197..8.546 rows=60 loops=1)
  Filter: ((measured_at >= '2026-01-02 12:00:00+00'::timestamp with time zone) AND (measured_at < '2026-01-02 13:00:00+00'::timestamp with time zone))
  Rows Removed by Filter: 99940
  Buffers: shared hit=1220
Planning:
  Buffers: shared hit=32
Planning Time: 0.242 ms
Execution Time: 8.580 ms
```

**Аналіз:** Через відсутність індексу PostgreSQL виконав повне послідовне сканування всієї таблиці (`Seq Scan`). Прочитано **1220 сторінок пам'яті** (`shared hit=1220`), відфільтровано та відкинуто **99 940 рядків**. Час виконання склав **8.580 ms**.

---

### 3.4. Дослід 2. Оптимізація вибірки індексом B-tree

Створення звичайного B-tree індексу за часовою міткою:
```sql
CREATE INDEX lr09_time_btree ON lab09_pr.readings (measured_at);
```

Повторний запуск ідентичного запиту:
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, sensor_id, temperature
FROM lab09_pr.readings
WHERE measured_at >= TIMESTAMPTZ '2026-01-02 12:00+00'
  AND measured_at <  TIMESTAMPTZ '2026-01-02 13:00+00';
```

**Фактичний план виконання з логу:**
```text
Index Scan using lr09_time_btree on readings  (cost=0.29..3.61 rows=56 width=18) (actual time=1.528..2.337 rows=60 loops=1)
  Index Cond: ((measured_at >= '2026-01-02 12:00:00+00'::timestamp with time zone) AND (measured_at < '2026-01-02 13:00:00+00'::timestamp with time zone))
  Buffers: shared hit=2 read=3
Planning:
  Buffers: shared hit=15 read=1
Planning Time: 1.498 ms
Execution Time: 2.371 ms
```

**Аналіз порівняння Досліду 1 та Досліду 2:**
- План змінився з `Seq Scan` на **`Index Scan using lr09_time_btree`**.
- Кількість звернень до буферів блоків скоротилася з **1220 блоків** до **5 блоків** (`shared hit=2 read=3`), тобто **в 244 рази менше роботи для пам'яті/диска**!
- Фактичний час виконання скоротився з `8.580 ms` до `2.371 ms` (прискорення **3.62x**).

---

### 3.5. Дослід 3. Багатоколонковий фільтр та складений індекс (Composite Index)

Пошук показів конкретного сенсора (`sensor_id = 42`) за добу (02.01.2026). Очікується 15 записів.

#### 1. План до створення складеного індексу:
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT sensor_id, measured_at, temperature
FROM lab09_pr.readings
WHERE sensor_id = 42
  AND measured_at >= TIMESTAMPTZ '2026-01-02 00:00+00'
  AND measured_at <  TIMESTAMPTZ '2026-01-03 00:00+00';
```

**Фактичний результат з логу:**
```text
Index Scan using lr09_time_btree on readings  (cost=0.29..52.46 rows=13 width=18) (actual time=1.994..7.032 rows=15 loops=1)
  Index Cond: ((measured_at >= '2026-01-02 00:00:00+00'::timestamp with time zone) AND (measured_at < '2026-01-03 00:00:00+00'::timestamp with time zone))
  Filter: (sensor_id = 42)
  Rows Removed by Filter: 1425
  Buffers: shared hit=22 read=3
Planning Time: 8.159 ms
Execution Time: 10.927 ms
```
*Проблема:* Індекс за часом знаходить усі 1440 вимірювань за добу, після чого PostgreSQL змушений вичитувати кожен рядок із таблиці та відкидати непотрібні датчики (`Rows Removed by Filter: 1425`).

#### 2. Створення складеного індексу та повторний замір:
```sql
CREATE INDEX lr09_sensor_time_btree ON lab09_pr.readings (sensor_id, measured_at);
```

**Фактичний результат з логу:**
```text
Index Scan using lr09_sensor_time_btree on readings  (cost=0.42..16.11 rows=13 width=18) (actual time=3.322..3.415 rows=15 loops=1)
  Index Cond: ((sensor_id = 42) AND (measured_at >= '2026-01-02 00:00:00+00'::timestamp with time zone) AND (measured_at < '2026-01-03 00:00:00+00'::timestamp with time zone))
  Buffers: shared hit=15 read=3
Planning:
  Buffers: shared hit=19 read=1
Planning Time: 1.334 ms
Execution Time: 3.465 ms
```

**Аналіз:**
- Обидва предикати (`sensor_id = 42` та діапазон часу) об'єднані в `Index Cond`.
- Кількість відкинутих рядків (`Rows Removed by Filter`) стала рівною **0**.
- Час виконання скоротився з `10.927 ms` до `3.465 ms` (прискорення **3.15x**).

---

### 3.6. Дослід 4. Оптимізація вибірки рідкісних станів через частковий індекс (Partial Index)

Завдання: знайти 20 найпізніших невалідних показів (`WHERE NOT is_valid ORDER BY measured_at DESC LIMIT 20`). Невалідних рядків усього 200 із 100 000 (0.2%).

#### 1. План до створення часткового індексу:
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, sensor_id, measured_at
FROM lab09_pr.readings
WHERE NOT is_valid
ORDER BY measured_at DESC
LIMIT 20;
```

**Фактичний результат з логу:**
```text
Limit  (cost=0.29..356.02 rows=20 width=20) (actual time=1.890..48.802 rows=20 loops=1)
  Buffers: shared hit=144 read=27
  ->  Index Scan Backward using lr09_time_btree on readings  (cost=0.29..3023.99 rows=170 width=20) (actual time=1.888..48.789 rows=20 loops=1)
        Filter: (NOT is_valid)
        Rows Removed by Filter: 9481
        Buffers: shared hit=144 read=27
Planning:
  Buffers: shared hit=17
Planning Time: 5.645 ms
Execution Time: 48.846 ms
```
*Проблема:* СУБД сканує індекс за часом у зворотному напрямку, вичитує сторінки таблиці та відкидає 9481 валідний рядок, перш ніж знайти 20 невалідних! Час склав **48.846 ms**, задіяно 171 блок.

#### 2. Створення часткового індексу та повторний замір:
```sql
CREATE INDEX lr09_invalid_partial ON lab09_pr.readings (measured_at DESC) WHERE NOT is_valid;
```

**Фактичний результат з логу:**
```text
Limit  (cost=0.14..1.07 rows=20 width=20) (actual time=1.232..1.259 rows=20 loops=1)
  Buffers: shared hit=20 read=1
  ->  Index Scan using lr09_invalid_partial on readings  (cost=0.14..7.99 rows=170 width=20) (actual time=1.231..1.255 rows=20 loops=1)
        Buffers: shared hit=20 read=1
Planning:
  Buffers: shared hit=15 read=1
Planning Time: 0.881 ms
Execution Time: 1.311 ms
```

**Аналіз:**
- Частковий індекс зберігає посилання виключно на 200 невалідних записів. Його фізичний розмір на диску становить лише **16 kB**.
- Час виконання скоротився з `48.846 ms` до `1.311 ms` (прискорення **37.26x**).
- Кількість прочитаних сторінок пам'яті скоротилася зі 171 блоку до **21 блоку**.

---

### 3.7. Дослід 5. Пошук у масивах (`tags text[]`) за допомогою інвертованого індексу GIN

Завдання: знайти вимірювання, що містять у масиві тег `alarm` (`tags @> ARRAY['alarm']::text[]`).

#### 1. План без GIN індексу:
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, measured_at
FROM lab09_pr.readings
WHERE tags @> ARRAY['alarm']::text[];
```

**Фактичний результат з логу:**
```text
Seq Scan on readings  (cost=0.00..2470.00 rows=170 width=16) (actual time=4.617..319.221 rows=200 loops=1)
  Filter: (tags @> '{alarm}'::text[])
  Rows Removed by Filter: 99800
  Buffers: shared hit=1220
Planning Time: 17.968 ms
Execution Time: 324.688 ms
```
*Проблема:* B-tree не підтримує пошук входження елемента в масив. Виконується повний `Seq Scan` із фільтрацією кожного масиву, час сягнув катастрофічних **324.688 ms**.

#### 2. Створення індексу GIN та повторний замір:
```sql
CREATE INDEX lr09_tags_gin ON lab09_pr.readings USING gin (tags);
```

**Фактичний результат з логу:**
```text
Bitmap Heap Scan on readings  (cost=12.18..183.46 rows=170 width=16) (actual time=0.056..0.327 rows=200 loops=1)
  Recheck Cond: (tags @> '{alarm}'::text[])
  Heap Blocks: exact=200
  Buffers: shared hit=202
  ->  Bitmap Index Scan on lr09_tags_gin  (cost=0.00..12.13 rows=170 width=0) (actual time=0.030..0.030 rows=200 loops=1)
        Index Cond: (tags @> '{alarm}'::text[])
        Buffers: shared hit=2
Planning:
  Buffers: shared hit=1
Planning Time: 0.095 ms
Execution Time: 0.363 ms
```

**Аналіз:**
- GIN індекс ставить у відповідність слову `'alarm'` список покажчиків на 200 рядків.
- Вузол `Bitmap Index Scan` звертається лише до 2 сторінок індексу (`Buffers: shared hit=2`).
- Час виконання впав із `324.688 ms` до **`0.363 ms`** — прискорення у **894.46 раза**!

---

### 3.8. Дослід 6 (Додаткове А). Компактний індекс діапазонів блоків BRIN

Видалення конкуруючих індексів B-tree за часом для чистоти експерименту:
```sql
DROP INDEX IF EXISTS lab09_pr.lr09_time_btree;
DROP INDEX IF EXISTS lab09_pr.lr09_sensor_time_btree;

CREATE INDEX lr09_time_brin
ON lab09_pr.readings USING brin (measured_at)
WITH (pages_per_range = 32);
```

Виконання діапазонного пошуку (1 година, 60 рядків):
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, sensor_id
FROM lab09_pr.readings
WHERE measured_at >= TIMESTAMPTZ '2026-01-02 12:00+00'
  AND measured_at <  TIMESTAMPTZ '2026-01-02 13:00+00';
```

**Фактичний результат з логу:**
```text
Bitmap Heap Scan on readings  (cost=3.32..1261.78 rows=56 width=12) (actual time=0.323..0.388 rows=60 loops=1)
  Recheck Cond: ((measured_at >= '2026-01-02 12:00:00+00'::timestamp with time zone) AND (measured_at < '2026-01-02 13:00:00+00'::timestamp with time zone))
  Rows Removed by Index Recheck: 2564
  Heap Blocks: lossy=32
  Buffers: shared hit=37
  ->  Bitmap Index Scan on lr09_time_brin  (cost=0.00..3.31 rows=2564 width=0) (actual time=0.032..0.033 rows=320 loops=1)
        Index Cond: ((measured_at >= '2026-01-02 12:00:00+00'::timestamp with time zone) AND (measured_at < '2026-01-02 13:00:00+00'::timestamp with time zone))
        Buffers: shared hit=5
Planning:
  Buffers: shared hit=20
Planning Time: 0.777 ms
Execution Time: 0.422 ms
```

**Аналіз роботи BRIN:**
- BRIN зберігає лише min/max часової мітки для кожного діапазону з 32 сторінок таблиці.
- `Bitmap Index Scan on lr09_time_brin` витратив лише **5 буферів**, щоб відібрати 32 сторінки, що потенційно містять потрібний часовий проміжок.
- `Bitmap Heap Scan` зчитав відібрані блоки (`Heap Blocks: lossy=32`, `shared hit=37`) та за допомогою секції `Recheck Cond` відкинув рядки, що виходять за межі 1 години (`Rows Removed by Index Recheck: 2564`).
- Час виконання склав **0.422 ms** (прискорення у **20.33 раза** порівняно з Seq Scan `8.580 ms`).

---

### 3.9. Дослід 7 (Додаткове Б). Дослідження алгоритму з'єднання таблиць (JOIN)

Агрегація вимірювань для перших 10 датчиків:
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.sensor_code, COUNT(*) AS number_of_readings
FROM lab09_pr.sensors AS s
JOIN lab09_pr.readings AS r ON r.sensor_id = s.id
WHERE s.id <= 10
GROUP BY s.sensor_code
ORDER BY s.sensor_code;
```

**Фактичний результат з логу:**
```text
Sort  (cost=2541.22..2541.24 rows=9 width=16) (actual time=45.319..45.322 rows=10 loops=1)
  Sort Key: s.sensor_code
  Sort Method: quicksort  Memory: 25kB
  Buffers: shared hit=1221
  ->  HashAggregate  (cost=2540.99..2541.08 rows=9 width=16) (actual time=43.935..43.941 rows=10 loops=1)
        Group Key: s.sensor_code
        Batches: 1  Memory Usage: 24kB
        Buffers: shared hit=1221
        ->  Hash Join  (cost=2.36..2495.99 rows=9000 width=8) (actual time=0.698..41.331 rows=10000 loops=1)
              Hash Cond: (r.sensor_id = s.id)
              Buffers: shared hit=1221
              ->  Seq Scan on readings r  (cost=0.00..2220.00 rows=100000 width=4) (actual time=0.039..19.460 rows=100000 loops=1)
                    Buffers: shared hit=1220
              ->  Hash  (cost=2.25..2.25 rows=9 width=12) (actual time=0.025..0.026 rows=10 loops=1)
                    Buckets: 1024  Batches: 1  Memory Usage: 9kB
                    Buffers: shared hit=1
```

**Аналіз алгоритму з'єднання:**
- Планувальник побудував хеш-таблицю в пам'яті для 10 відфільтрованих датчиків (`Hash`, 9 kB RAM).
- Для з'єднання з `readings` (оскільки на полі зовнішнього ключа `sensor_id` у даний момент індекс був відсутній) СУБД застосувала повне послідовне сканування `readings` (`Seq Scan`, 1220 блоків) та алгоритм **`Hash Join`**.
- Результати згруповано за допомогою `HashAggregate` та фінально впорядковано швидким сортуванням `quicksort`. Загальний час склав **45.322 ms**.

---

### 3.10. Дослід 8 (Творче). Покривний індекс (Covering Index) та `Index Only Scan`

Створення індексу з фразою `INCLUDE (temperature)` та оновлення карти видимості Visibility Map:
```sql
CREATE INDEX lr09_sensor_time_covering
ON lab09_pr.readings (sensor_id, measured_at)
INCLUDE (temperature);

VACUUM (ANALYZE) lab09_pr.readings;
```

Вибірка даних:
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT sensor_id, measured_at, temperature
FROM lab09_pr.readings
WHERE sensor_id = 42
  AND measured_at >= TIMESTAMPTZ '2026-01-02 00:00+00'
  AND measured_at <  TIMESTAMPTZ '2026-01-03 00:00+00';
```

**Фактичний результат з логу:**
```text
Index Only Scan using lr09_sensor_time_covering on readings  (cost=0.42..1.81 rows=13 width=18) (actual time=1.951..1.954 rows=15 loops=1)
  Index Cond: ((sensor_id = 42) AND (measured_at >= '2026-01-02 00:00:00+00'::timestamp with time zone) AND (measured_at < '2026-01-03 00:00:00+00'::timestamp with time zone))
  Heap Fetches: 0
  Buffers: shared hit=1 read=3
Planning:
  Buffers: shared hit=32 dirtied=3
Planning Time: 1.738 ms
Execution Time: 1.983 ms
```

**Аналіз:**
- Отримано найефективніший вузол читання — **`Index Only Scan`**.
- Показник **`Heap Fetches: 0`** підтверджує, що сервер жодного разу не звернувся до сторінок самої таблиці (`readings`). Усі три необхідні стовпці (`sensor_id`, `measured_at`, `temperature`) були витягнуті безпосередньо з листових сторінок покривного індексу.
- Час виконання склав **1.983 ms** (у 5.51 раза швидше за базовий B-tree `10.927 ms`).

---

### 3.11. Системний аудит індексів схеми через `pg_indexes`

```sql
SELECT tablename, indexname, indexdef 
FROM pg_indexes 
WHERE schemaname = 'lab09_pr'
ORDER BY tablename, indexname;
```

**Фактичний результат з логу:**
```text
 tablename |         indexname         |                                                        indexdef                                                        
-----------+---------------------------+------------------------------------------------------------------------------------------------------------------------
 readings  | lr09_invalid_partial      | CREATE INDEX lr09_invalid_partial ON lab09_pr.readings USING btree (measured_at DESC) WHERE (NOT is_valid)
 readings  | lr09_sensor_time_covering | CREATE INDEX lr09_sensor_time_covering ON lab09_pr.readings USING btree (sensor_id, measured_at) INCLUDE (temperature)
 readings  | lr09_tags_gin             | CREATE INDEX lr09_tags_gin ON lab09_pr.readings USING gin (tags)
 readings  | lr09_time_brin            | CREATE INDEX lr09_time_brin ON lab09_pr.readings USING brin (measured_at) WITH (pages_per_range='32')
 readings  | readings_pkey             | CREATE UNIQUE INDEX readings_pkey ON lab09_pr.readings USING btree (id)
 sensors   | sensors_pkey              | CREATE UNIQUE INDEX sensors_pkey ON lab09_pr.sensors USING btree (id)
 sensors   | sensors_sensor_code_key   | CREATE UNIQUE INDEX sensors_sensor_code_key ON lab09_pr.sensors USING btree (sensor_code)
(7 rows)
```

---

## 4. Зведена матриця результатів вимірювань та аналіз фізичного розміру

### 4.1. Зведена таблиця продуктивності запитів

| № Досліду | Досліджуваний запит / індекс | К-сть рядків | План (До $\to$ Після) | Execution Time (До $\to$ Після), мс | Buffers shared (hit/read) (До $\to$ Після) | Коефіцієнт прискорення ($t_{\text{до}} / t_{\text{після}}$) |
|---|---|---|---|---|---|---|
| **Дослід 2** | B-tree за часом (`lr09_time_btree`) | 60 | `Seq Scan` $\to$ `Index Scan` | `8.580` $\to$ `2.371` мс | hit: 1220 read: 0 $\to$ hit: 2 read: 3 | **3.62 x** (блоки $\downarrow 244\times$) |
| **Дослід 3** | Складений індекс `(sensor_id, measured_at)` | 15 | `Index Scan (time + filter)` $\to$ `Index Scan (composite)` | `10.927` $\to$ `3.465` мс | hit: 22 read: 3 $\to$ hit: 15 read: 3 | **3.15 x** (фільтр: 1425 $\to$ 0 відкинутих) |
| **Дослід 4** | Частковий індекс `WHERE NOT is_valid` | 20 | `Index Scan Backward + Filter` $\to$ `Index Scan (partial)` | `48.846` $\to$ `1.311` мс | hit: 144 read: 27 $\to$ hit: 20 read: 1 | **37.26 x** (фільтр: 9481 $\to$ 0 відкинутих) |
| **Дослід 5** | GIN індекс для масивів `tags @> ['alarm']` | 200 | `Seq Scan` $\to$ `Bitmap Index Scan (GIN)` | `324.688` $\to$ `0.363` мс | hit: 1220 read: 0 $\to$ hit: 202 read: 0 | **894.46 x** (найбільший ефект) |
| **Додатково А**| BRIN за часом (`lr09_time_brin`) | 60 | `Seq Scan` $\to$ `Bitmap Index Scan (BRIN)` | `8.580` $\to$ `0.422` мс | hit: 1220 read: 0 $\to$ hit: 37 read: 0 | **20.33 x** (розмір 24 kB) |
| **Додатково Б**| JOIN датчиків і вимірювань (`s.id <= 10`) | 10 | `Hash Join (Seq Scan + Hash)` | `45.322` мс | hit: 1221 read: 0 | Базовий замір JOIN |
| **Творче (Етап 8)**| Покривний індекс `INCLUDE (temperature)` | 15 | `Index Scan` $\to$ `Index Only Scan (Heap Fetches: 0)` | `3.465` $\to$ `1.983` мс | hit: 15 read: 3 $\to$ hit: 1 read: 3 | **1.75 x** (5.51x до базового B-tree) |

---

### 4.2. Фізичні розміри об'єктів на диску (`pg_relation_size`)

```text
       object_name       |    size    
-------------------------+------------
 readings                | 9760 kB
 readings_pkey           | 2208 kB
 lr09_tags_gin           | 136 kB
 lr09_time_brin          | 24 kB
 lr09_invalid_partial    | 16 kB
 sensors_sensor_code_key | 16 kB
 sensors_pkey            | 16 kB
 sensors                 | 8192 bytes
 readings_id_seq         | 8192 bytes
```

**Висновки щодо розмірів:**
- BRIN займає лише **24 kB**, що у **92 рази менше** за класичний B-tree первинного ключа (2208 kB), демонструючи майже однаковий час вибірки.
- Частковий індекс `lr09_invalid_partial` займає всього **16 kB** (дві сторінки пам'яті), оскільки містить лише 200 записів із 100 000.

---

## 5. Відповіді на контрольні питання

### 1. Що таке індекс і чому він займає додаткове місце?

Індекс — це окрема фізична структура даних (наприклад, збалансоване дерево B-tree, бітова карта чи інвертований список), яка зберігає значення індексованих стовпців у впорядкованому вигляді разом із покажчиками на фізичне розташування рядків (`ctid`) у таблиці.  
Він займає додаткове місце на диску та в оперативній пам'яті (`shared_buffers`), оскільки вимагає зберігання власних 8-кілобайтних блоків пам'яті з вузлами дерева, ключами, метаданими та посиланнями на сторінки таблиці.

### 2. Чим відрізняються EXPLAIN і EXPLAIN ANALYZE?

- `EXPLAIN` формує оціночний план виконання запиту суто теоретично, ґрунтуючись на системній статистиці оптимізатора (`pg_statistic`), без фактичного запуску запиту. Відображає розрахункову вартість `cost` та очікувану кількість рядків `rows`.
- `EXPLAIN ANALYZE` дійсно виконує запит на сервері, заміряючи фактичний час виконання кожного вузла (`actual time`), кількість реально повернутих рядків (`actual rows`) та кількість оброблених сторінок пам'яті й диска (при вказанні опції `BUFFERS`).

### 3. Що означають Seq Scan і Index Scan?

- `Seq Scan` (Sequential Scan) — це послідовне зчитування всіх сторінок таблиці від першої до останньої з перевіркою умов фільтрації для кожного рядка. Ефективний, коли потрібно вичитати значну частку таблиці (понад 15–20%).
- `Index Scan` — це прохід по дереву індексу від кореня до листка для пошуку потрібного значення ключа з наступним негайним вичитуванням відповідного кортежу зі сторінки таблиці. Ефективний для високої селективності (вибірка одиничних рядків або вузьких інтервалів).

### 4. Чим GIN відрізняється від B-tree?

B-tree є збалансованим деревом скалярних значень (один рядок таблиці = один ключ в індексі) і призначений для операцій порівняння (`=`, `<`, `>`).  
GIN (Generalized Inverted Index) призначений для складених типів даних (масиви, JSONB, повнотекстовий пошук). Він розбиває вміст стовпця на складові елементи та створює інвертований список: для кожного унікального елемента зберігається перелік усіх рядків (`ctid`), у яких він зустрічається. Це забезпечує екстремальну швидкість перевірки оператора входження `@>`, але робить операції `INSERT`/`UPDATE` повільнішими.

### 5. Для чого потрібен частковий індекс?

Частковий індекс (`Partial Index`) містить посилання лише на ті рядки, що задовольняють умову предикату `WHERE condition`. Він використовується для оптимізації запитів до рідкісних статусів (наприклад, помилкові вимірювання `WHERE NOT is_valid` або незавершені замовлення). Частковий індекс займає мікроскопічний обсяг пам'яті (у нашій роботі — лише 16 kB проти мегабайтів повної таблиці) і не уповільнює вставку рядків, що не задовольняють його умову.

### 6. Чому PostgreSQL може не використати створений індекс?

Оптимізатор PostgreSQL використовує вартісну модель (Cost-based Optimizer). Він проігнорує індекс у таких випадках:
1. **Низька селективність запиту:** Якщо запит повертає значний відсоток рядків (наприклад, > 15–25%), послідовне зчитування блоків (`Seq Scan`) обходиться дешевше, ніж багатократний випадковий доступ через індекс.
2. **Малий розмір таблиці:** Якщо вся таблиця займає кілька сторінок, її читання цілком виконується швидше, ніж спуск по дереву індексу.
3. **Використання функцій над стовпцем:** Умова на кшталт `WHERE date(measured_at) = ...` блокує використання звичайного індексу за полем `measured_at` (потрібен індекс за виразом).
4. **Невідповідність типів даних:** Неявне приведення типів блокує використання операторів індексу.
5. **Застаріла статистика:** Якщо планувальник спирається на неактуальні дані каталогу `pg_statistic` (лікується викликом `ANALYZE`).

### + Додаткові питання:
- **У чому перевага BRIN?** BRIN зберігає лише екстремуми (`min`/`max`) для цілих пачок сторінок (32 або 128 блоків). Його розмір у десятки-сотні разів менший за B-tree (у лабораторній — лише 24 kB проти 2208 kB), що робить його незамінним для велетенських часових рядів.
- **Що забезпечує покривний індекс з `INCLUDE`?** Додавання неключових стовпців у листові блоки через `INCLUDE` дозволяє серверу отримати всі необхідні поля безпосередньо з індексу, повністю виключаючи читання таблиці (**Index Only Scan**, `Heap Fetches: 0`).

---

## 6. Загальні висновки

Під час виконання лабораторної роботи № 9 було досягнуто таких практичних результатів:

1. **Опанування інструментів профілювання:** На практиці освоєно застосування команди `EXPLAIN (ANALYZE, BUFFERS)`. Доведено важливість аналізу метрики звернень до блоків пам'яті (`shared hit/read`), оскільки саме мінімізація введення-виведення визначає реальну швидкодію СУБД.
2. **Підтвердження ефективності B-tree на діапазонах:** Створення B-tree індексу за полем часу трансформувало тривале сканування `Seq Scan` (8.580 ms) в `Index Scan` (2.371 ms), скоротивши звернення до блоків у 244 рази (з 1220 до 5 блоків).
3. **Демонстрація переваг складеного індексу:** Доведено, що правильне розміщення колонок у складеному індексі `(sensor_id, measured_at)` дозволяє одночасно відсікати точну рівність датчика та часовий інтервал, усунувши необхідність фільтрації 1425 зайвих рядків і прискоривши запит у 3.15 раза.
4. **Колосальна економія ресурсів частковими індексами:** Частковий індекс `lr09_invalid_partial` розміром лише 16 kB забезпечив прискорення у **37.26 раза** (з 48.846 ms до 1.311 ms), позбавивши планувальник необхідності сканувати 9481 валідний рядок.
5. **Неймовірна продуктивність GIN для масивів:** Застосування інвертованого індексу GIN для оператора входження `@>` скоротило час вибірки з 324.688 ms до 0.363 ms — прискорення у **894.46 раза**.
6. **Практична верифікація компактності BRIN:** Доведено, що для фізично впорядкованих часових даних індекс BRIN розміром лише 24 kB забезпечує прискорення у 20.33 раза, виступаючи ідеальною альтернативою B-tree для великих даних (Big Data).
7. **Реалізація Index Only Scan:** За допомогою фрази `INCLUDE (temperature)` досягнуто виконання запиту з показником `Heap Fetches: 0`, коли всі необхідні дані отримано виключно з індексу за 1.983 ms.
