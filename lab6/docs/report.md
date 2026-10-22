# Лабораторна робота № 6: Віконні функції, CTE, рекурсивні запити та представлення у PostgreSQL

**Дисципліна:** Бази даних  
**Користувач БД:** `illia`  
**База даних:** `lab6`  
**Схема БД:** `lab06`  
**Інфраструктура:** Docker Container (`postgres_db`, мережа `db_network`)  
**Клієнтське середовище:** CLI-клієнт `psql` (PostgreSQL 17)  

---

## 1. Мета роботи

1. Опанувати аналіз послідовностей вимірювань та часових рядів засобами SQL без згортання вихідних рядків вибірки.
2. Дослідити архітектуру віконних функцій (`OVER`, `PARTITION BY`, `ORDER BY`), вивчити відмінність між внутрішнім упорядкуванням вікна та зовнішнім сортуванням запиту.
3. Дослідити принципи функціонування функцій ранжування (`ROW_NUMBER()`, `RANK()`, `DENSE_RANK()`) та проаналізувати наслідки додавання первинних ключів у сортування рангу.
4. Засвоїти механіку функцій відносного зміщення (`LAG()`, `LEAD()`), дослідити фізичну семантику значення `NULL` та неприпустимість його заміни нулем без фізичного обґрунтування.
5. Вивчити анатомію меж рамок вікна, порівняти фізичне зміщення `ROWS` та логічний діапазон `RANGE` при наявності дублікатів часових міток.
6. Опанувати побудову ковзних середніх за кількістю вимірювань (`ROWS n PRECEDING`) та за фізичним часовим інтервалом (`RANGE INTERVAL '...' PRECEDING`).
7. Дослідити функції екстремальних значень вибірки (`FIRST_VALUE()`, `LAST_VALUE()`) та подолати пастку дефолтної рамки вікна за допомогою `UNBOUNDED FOLLOWING`.
8. Навчитися логічно структурувати багатоетапні запити через звичайні табличні вирази (CTE) для подолання обмеження заборони віконних функцій у `WHERE`.
9. Опанувати рекурсивний обхід ієрархічних деревоподібних структур довільної глибини (`WITH RECURSIVE`) із захистом від циклічного зациклення через масив шляху `ARRAY[id]` та предикат `ANY()`.
10. Дослідити практичну різницю між динамічними представленнями (`VIEW`) та збереженими на диску матеріалізованими представленнями (`MATERIALIZED VIEW`), включно з дослідженням життєвого циклу синхронізації через команду `REFRESH`.
11. Розробити власне аналітичне правило моніторингу випробувальних стендів у межах творчого завдання, розширити реляційну модель та верифікувати рішення на контрольних тестах.

---

## 2. Теоретичні відомості та архітектурний аналіз

### 2.1. Ізоляція схеми та ризики мутації `search_path` (Anti-pattern)

У СУБД PostgreSQL схема (`schema`) є логічним простором імен усередині бази даних. Системна змінна `search_path` визначає порядок перегляду схем, коли користувач викликає таблицю за простим некваліфікованим іменем:

#### Чому `SET search_path` є антипатерном:
1. **Сесійна волатильність:** Зміна параметра діє лише в межах поточного сеансу. При перепідключенні клієнта, відкритті нової вкладки в psql або виконанні запитів через пул з'єднань (PgBouncer, HikariCP) налаштування скидається до системного (`"$user", public`). Усі запити без явного префікса зазнають збою з фатальною помилкою `42P01: relation does not exist`.
2. **Вразливість безпеки (Search-path Hijacking):** Якщо недобросовісний користувач створить однойменну таблицю або функцію в загальнодоступній схемі `public`, ядро PostgreSQL виконає підмінений об'єкт замість очікуваного.
3. **Непрозорість міграцій та аудиту:** При аналізі SQL-логів неможливо детерміновано визначити, до якої саме таблиці звертається оператор, якщо назву схеми опущено.

**Рекомендований стандарт:** Повна відмова від мутації `search_path` на користь суворої явної двокомпонентної кваліфікації кожного об'єкта назвою схеми: `lab06.equipment`, `lab06.sensors`, `lab06.readings`.

---

### 2.2. Архітектура віконних функцій: збереження рядків проти `GROUP BY`

Ключова архітектурна відмінність між оператором групування `GROUP BY` та віконними функціями (`OVER`) полягає в збереженні гранулярності даних:

```text
       Вихідні покази датчика T-01 (6 рядків):
       ┌────┬───────────┬─────────────┐
       │ id │ sensor_id │ temperature │
       ├────┼───────────┼─────────────┤
       │ 1  │     1     │    20.0     │
       │ 2  │     1     │    22.0     │
       │ 3  │     1     │    22.0     │
       │ 4  │     1     │    24.0     │
       │ 5  │     1     │    23.0     │
       │ 6  │     1     │    25.0     │
       └────┴───────────┴─────────────┘
                     │
         ┌───────────┴───────────┐
         ▼                       ▼
    GROUP BY sensor_id        AVG(temperature) OVER (PARTITION BY sensor_id)
   Згортає вибірку           Зберігає всі вихідні рядки
   ┌───────────┬────────┐    ┌────┬───────────┬─────────────┬────────────┐
   │ sensor_id │  avg   │    │ id │ sensor_id │ temperature │ sensor_avg │
   ├───────────┼────────┤    ├────┼───────────┼─────────────┼────────────┤
   │     1     │ 22.67  │    │ 1  │     1     │    20.0     │   22.67    │
   └───────────┴────────┘    │ 2  │     1     │    22.0     │   22.67    │
   (Втрачено окремі покази)  │ .. │    ...    │     ...     │   22.67    │
                             └────┴───────────┴─────────────┴────────────┘
                             (Кожен показ отримує контекстне середнє)
```

- **`PARTITION BY`:** Розбиває вибірку на незалежні логічні вікна (розділи).
- **`ORDER BY` в `OVER(...)`:** Задає внутрішній порядок обчислення функції у вікні.
- **Зовнішній `ORDER BY` запиту:** Сортує остаточний результат на етапі виведення й жодним чином не впливає на обчислення віконних функцій.

---

### 2.3. Алгоритми ранжування: `ROW_NUMBER()` vs `RANK()` vs `DENSE_RANK()`

1. **`ROW_NUMBER()`:** Присвоює унікальний порядковий номер кожному рядку в межах розділу (1, 2, 3, 4, 5, 6). При однакових значеннях сортування порядок є недетермінованим, якщо не додано тай-брейкер (наприклад, `measured_at, id`).
2. **`RANK()`:** Присвоює однаковий ранг однаковим значенням. При переході до наступного значення формується пропуск у нумерації на кількість дублікатів (1, 2, 3, **4, 4, 6**).
3. **`DENSE_RANK()`:** Присвоює однаковий ранг однаковим значенням, але не створює пропусків у рангах (1, 2, 3, **4, 4, 5**).

> [!WARNING]
> **Втрата сенсу ранжування:**
> Додавання унікального первинного ключа `id` в `ORDER BY` всередині `RANK()` або `DENSE_RANK()` робить кожен рядок штучно унікальним. Як наслідок, однакові температури втрачають спільне місце, а функції перетворюються на звичайний `ROW_NUMBER()`.

---

### 2.4. Семантика функцій зміщення `LAG()` і `LEAD()`, значення `NULL`

- `LAG(value, [offset, [default]])`: повертає значення поля з попереднього рядка відносно поточного в межах розділу.
- `LEAD(value, [offset, [default]])`: повертає значення з наступного рядка.
- **Фізичний зміст `NULL`:** Якщо сусідній показ відсутній (перший або останній запис), функція повертає `NULL`. Підстановка нуля замість відсутнього значення (`COALESCE(LAG(value), 0)`) є грубою інженерною помилкою: різниця між поточною температурою $20^\circ\text{C}$ та відсутнім попереднім вимірюванням перетворилася б на штучний стрибок $+20^\circ\text{C}$, що повністю спотворює аналіз динаміки.

---

### 2.5. Анатомія рамки вікна: `ROWS` проти `RANGE`

Рамка вікна (`window frame`) визначає підмножину рядків розділу, що беруть участь в агрегації для поточного кортежу:
- **`ROWS`:** Визначає фізичну кількість рядків відносно поточної позиції.
- **`RANGE`:** Визначає логічний діапазон значень стовпця сортування. Якщо кілька рядків мають однакове значення сортування (наприклад, часові мітки `08:20`), рамка `RANGE ... CURRENT ROW` включає всі зв'язані рядки-дублікати даної позиції одночасно.

> [!IMPORTANT]
> **Пастка дефолтної рамки PostgreSQL:**
> Якщо в операторі `OVER` зазначено `ORDER BY`, але пропущено опис меж, PostgreSQL за замовчуванням застосовує:  
> `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`.  
> Для накопичувальних підрахунків рядок за рядком слід завжди явно зазначати `ROWS`.

---

### 2.6. Ковзні середні: фізична кількість записів проти часового інтервалу

- `ROWS BETWEEN 2 PRECEDING AND CURRENT ROW`: враховує поточний та до двох попередніх фізичних записів незалежно від часу їх надходження.
- `RANGE BETWEEN INTERVAL '20 minutes' PRECEDING AND CURRENT ROW`: враховує всі вимірювання, час яких потрапляє в часове вікно $[t - 20\text{ хв}, t]$.
- При нерегулярній частоті фіксації або пропуску вимірювань результати суттєво відрізняються, тому поруч із середнім обов'язково контролюють кількість врахованих точок (`COUNT(*)`).

---

### 2.7. Крайні значення вибірки: `FIRST_VALUE()`, `LAST_VALUE()` та пастка рамки

- `FIRST_VALUE(col)`: повертає значення першого рядка поточної рамки вікна.
- `LAST_VALUE(col)`: повертає значення останнього рядка поточної рамки вікна.
- **Пастка `LAST_VALUE`:** Якщо функцію викликати з дефолтною рамкою, останнім рядком рамки є поточний рядок (`CURRENT ROW`), тому `LAST_VALUE()` повертає власне значення поточного кортежу. Щоб отримати істинне кінцеве значення розділу, рамку необхідно явно розширити:  
  `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING`.

---

### 2.8. CTE як засіб розділення обчислень та фільтрації

Згідно зі стандартом SQL, віконні функції не можна використовувати безпосередньо у блоці `WHERE` або `HAVING` того самого запиту, оскільки фільтрація логічно передує віконним обчисленням.  
Конструкція `WITH name AS (...)` дозволяє розбити обчислення на два ізольовані етапи:
1. CTE розраховує віконні значення (наприклад, `ROW_NUMBER() AS rn` або `LAG(value) AS prev_value`).
2. Основний `SELECT` фільтрує готові стовпці (`WHERE rn = 1` або `WHERE ABS(delta) >= 2.0`).

---

### 2.9. Рекурсивні запити (`WITH RECURSIVE`): механіка та захист від циклів

Рекурсивний CTE складається з двох частин, об'єднаних `UNION ALL`:
1. **Якірний член (Anchor member):** Стартовий запит, що повертає корені ієрархії (`WHERE parent_id IS NULL` або стартовий вузол стенда).
2. **Рекурсивний член (Recursive member):** Запит, що поєднує попередній крок з вихідною таблицею (`JOIN tree t ON e.parent_id = t.id`). Обчислення зупиняється, коли черговий крок повертає порожній набір рядків.
- **Захист від зациклення:** Для уникнення нескінченного циклу у разі некоректних даних формується масив відвіданих вузлів `ARRAY[id] AS path`, а рекурсивний крок обмежується умовою `WHERE NOT (e.id = ANY(t.path))`.

---

### 2.10. Порівняння `VIEW` та `MATERIALIZED VIEW`

| Критерій | Звичайне представлення (`VIEW`) | Матеріалізоване представлення (`MATERIALIZED VIEW`) |
| :--- | :--- | :--- |
| **Фізичне збереження** | Зберігається лише текст запиту (AST) | Зберігається текст запиту та його обчислений результат на диску |
| **Продуктивність читання** | Залежить від складності базового запиту | Миттєве читання як зі звичайної фізичної таблиці |
| **Актуальність даних** | Абсолютна (відображає зміни на момент виконання) | Статична (дані фіксуються на момент створення або оновлення) |
| **Процедура оновлення** | Автоматична під час кожного запиту | Виключно явної командою `REFRESH MATERIALIZED VIEW` |
| **Блокування під час оновлення** | Відсутнє | Звичайний `REFRESH` блокує читання таблиці іншими сесіями |

---

### 2.11. Зведена архітектурна таблиця конструкцій

| Конструкція | Синтаксичний вираз | Основне призначення | Практичний ефект у роботі |
| :--- | :--- | :--- | :--- |
| **`OVER (PARTITION BY)`**| `AVG(val) OVER (PARTITION BY s_id)` | Агрегація без схлопування вибірки | Розрахунок відхилення вимірювання від середнього датчика |
| **`ROW_NUMBER()`** | `ROW_NUMBER() OVER (...)` | Унікальна наскрізна нумерація | Відбір найновіших вимірювань через CTE (`rn = 1`) |
| **`RANK()`** | `RANK() OVER (ORDER BY val DESC)` | Ранжування з пропусками | Присвоєння спільного місця однаковим температурам |
| **`DENSE_RANK()`** | `DENSE_RANK() OVER (...)` | Щільне ранжування без пропусків | Ранжування датчиків за амплітудою стрибків нагріву |
| **`LAG()` / `LEAD()`** | `LAG(val) OVER w` | Доступ до сусідніх рядків розділу | Обчислення різниці $\Delta = V - \text{prev\_val}$ |
| **`ROWS BETWEEN`** | `ROWS BETWEEN UNBOUNDED ...` | Фізичне накопичувальне вікно | Підрахунок накопиченої кількості перевищень ліміту |
| **`RANGE INTERVAL`** | `RANGE BETWEEN INTERVAL '20 min'` | Часове вікно ковзного згладжування | Розрахунок ковзного середнього за 20-хвилинним інтервалом |
| **`LAST_VALUE()`** | `LAST_VALUE() OVER w_full` | Отримання фінального показника | Пошук підсумкової температури всього циклу спостережень |
| **`WITH` (CTE)** | `WITH cte AS (...) SELECT ...` | Багатоетапна логічна декомпозиція | Ізоляція віконних обчислень перед фільтрацією в `WHERE` |
| **`WITH RECURSIVE`** | `WITH RECURSIVE tree AS (...)` | Обхід деревоподібних ієрархій | Спуск по дереву обладнання стенда до всіх дочірніх датчиків |
| **`VIEW`** | `CREATE VIEW v_name AS ...` | Динамічний збережений звіт | Постійний доступ до актуального зведення параметрів |
| **`MATERIALIZED VIEW`**| `CREATE MATERIALIZED VIEW ...` | Фізичний знімок важкого звіту | Швидке читання аналітики з контрольованим `REFRESH` |

---

## 3. Протокол виконання та аналіз фактичних логів сесії

Усі команди виконано в контейнері `postgres_db` у базі даних `lab6` під користувачем `illia`. Журнал сесії зафіксовано у файлі [savings.txt](file:///home/mafi2/Projects/DataBase-discipline/lab6/savings.txt).

---

### 3.1. Перевірка середовища сесії та скидання схеми `lab06`

```sql
SHOW search_path;
SELECT current_database(), current_user, pg_backend_pid();
DROP SCHEMA IF EXISTS lab06 CASCADE;
```

Фактичний результат з журналу виконання:

```text
SHOW search_path;
   search_path   
-----------------
 "$user", public
(1 row)

SELECT current_database(), current_user, pg_backend_pid();
 current_database | current_user | pg_backend_pid 
------------------+--------------+----------------
 lab6             | illia        |            453
(1 row)

DROP SCHEMA IF EXISTS lab06 CASCADE;
DROP SCHEMA
```

Параметр `search_path` залишено незмінним. Усі подальші таблиці створюються в схемі `lab06`.

---

### 3.2. Створення схеми, таблиць та індексів (Розділ 1)

```sql
CREATE SCHEMA IF NOT EXISTS lab06;

CREATE TABLE IF NOT EXISTS lab06.equipment (
    id        integer PRIMARY KEY,
    parent_id integer REFERENCES lab06.equipment(id),
    name      text NOT NULL,
    CHECK (parent_id IS NULL OR parent_id <> id)
);

CREATE TABLE IF NOT EXISTS lab06.sensors (
    id           integer PRIMARY KEY,
    sensor_code  text NOT NULL UNIQUE,
    equipment_id integer NOT NULL REFERENCES lab06.equipment(id),
    limit_value  numeric(5,1) NOT NULL
);

CREATE TABLE IF NOT EXISTS lab06.readings (
    id          integer PRIMARY KEY,
    sensor_id   integer NOT NULL REFERENCES lab06.sensors(id),
    measured_at timestamp NOT NULL,
    value       numeric(5,1) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_equipment_parent_id ON lab06.equipment(parent_id);
CREATE INDEX IF NOT EXISTS idx_sensors_equipment_id ON lab06.sensors(equipment_id);
CREATE INDEX IF NOT EXISTS idx_readings_sensor_measured ON lab06.readings(sensor_id, measured_at, id);
```

Фактичний результат з журналу:

```text
CREATE SCHEMA
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE INDEX
CREATE INDEX
CREATE INDEX
```

Створено таблиці з обмеженнями цілісності (зовнішні ключі, заборона самопосилання) та B-tree індекси для прискорення віконних операцій.

---

### 3.3. Наповнення базовими даними та верифікація (Розділ 2)

```sql
BEGIN;
INSERT INTO lab06.equipment (id, parent_id, name) VALUES
    (1, NULL, 'Навчальна лабораторія'),
    (2, 1,    'Стенд А'),
    (3, 1,    'Стенд Б'),
    (4, 2,    'Нагрівальна камера'),
    (5, 2,    'Охолоджувальний блок'),
    (6, 3,    'Повітряний канал');

INSERT INTO lab06.sensors (id, sensor_code, equipment_id, limit_value) VALUES
    (1, 'T-01', 4, 22.0),
    (2, 'T-02', 5, 30.0),
    (3, 'T-03', 6, 19.0);

INSERT INTO lab06.readings (id, sensor_id, measured_at, value) VALUES
    (1,  1, '2026-10-01 08:00', 20.0),
    (2,  1, '2026-10-01 08:10', 22.0),
    (3,  1, '2026-10-01 08:20', 22.0),
    (4,  1, '2026-10-01 08:20', 24.0),
    (5,  1, '2026-10-01 08:40', 23.0),
    (6,  1, '2026-10-01 08:50', 25.0),
    (7,  2, '2026-10-01 08:00', 28.0),
    (8,  2, '2026-10-01 08:10', 29.0),
    (9,  2, '2026-10-01 08:20', 31.0),
    (10, 2, '2026-10-01 08:30', 31.0),
    (11, 2, '2026-10-01 08:40', 30.0),
    (12, 2, '2026-10-01 08:50', 29.0),
    (13, 3, '2026-10-01 08:00', 18.0),
    (14, 3, '2026-10-01 08:10', 18.0),
    (15, 3, '2026-10-01 08:20', 19.0),
    (16, 3, '2026-10-01 08:30', 17.0),
    (17, 3, '2026-10-01 08:40', 18.0),
    (18, 3, '2026-10-01 08:50', 20.0);
COMMIT;

SELECT sensor_id,
       COUNT(*)             AS reading_count,
       ROUND(AVG(value), 2) AS avg_value
FROM lab06.readings
GROUP BY sensor_id
ORDER BY sensor_id;
```

Фактичний результат з журналу:

```text
INSERT 0 6
INSERT 0 3
INSERT 0 18
COMMIT
 sensor_id | reading_count | avg_value 
-----------+---------------+-----------
         1 |             6 |     22.67
         2 |             6 |     29.67
         3 |             6 |     18.33
(3 rows)
```

Базовий набір сформовано: рівно по 6 вимірювань на кожен із трьох сенсорів.

---

### 3.4. Віконне середнє та відставання від максимуму (Приклад 1)

#### 1. Розрахунок відхилення вимірювань від середнього свого датчика:
```sql
SELECT id, sensor_id, measured_at, value,
       ROUND(AVG(value) OVER (
           PARTITION BY sensor_id
       ), 2) AS sensor_avg,
       ROUND(value - AVG(value) OVER (
           PARTITION BY sensor_id
       ), 2) AS deviation
FROM lab06.readings
ORDER BY sensor_id, measured_at, id;
```

Фактичний фрагмент результату для датчика 1 (`T-01`):

```text
 id | sensor_id |     measured_at     | value | sensor_avg | deviation 
----+-----------+---------------------+-------+------------+-----------
  1 |         1 | 2026-10-01 08:00:00 |  20.0 |      22.67 |     -2.67
  2 |         1 | 2026-10-01 08:10:00 |  22.0 |      22.67 |     -0.67
  3 |         1 | 2026-10-01 08:20:00 |  22.0 |      22.67 |     -0.67
  4 |         1 | 2026-10-01 08:20:00 |  24.0 |      22.67 |      1.33
  5 |         1 | 2026-10-01 08:40:00 |  23.0 |      22.67 |      0.33
  6 |         1 | 2026-10-01 08:50:00 |  25.0 |      22.67 |      2.33
...
(18 rows)
```

#### 2. Самостійна перевірка 1: Відставання від максимуму свого датчика:
```sql
SELECT id, sensor_id, measured_at, value,
       MAX(value) OVER (
           PARTITION BY sensor_id
       ) AS sensor_max,
       ROUND(value - MAX(value) OVER (
           PARTITION BY sensor_id
       ), 2) AS lag_from_max
FROM lab06.readings
ORDER BY sensor_id, measured_at, id;
```

Фактичний результат з журналу:

```text
 id | sensor_id |     measured_at     | value | sensor_max | lag_from_max 
----+-----------+---------------------+-------+------------+--------------
  1 |         1 | 2026-10-01 08:00:00 |  20.0 |       25.0 |        -5.00
  2 |         1 | 2026-10-01 08:10:00 |  22.0 |       25.0 |        -3.00
  3 |         1 | 2026-10-01 08:20:00 |  22.0 |       25.0 |        -3.00
  4 |         1 | 2026-10-01 08:20:00 |  24.0 |       25.0 |        -1.00
  5 |         1 | 2026-10-01 08:40:00 |  23.0 |       25.0 |        -2.00
  6 |         1 | 2026-10-01 08:50:00 |  25.0 |       25.0 |         0.00
...
(18 rows)
```

Кількість рядків залишилася незмінною (18), а значення `lag_from_max` показує відставання від пікового нагріву.

---

### 3.5. Функції ранжування та вплив первинного ключа (Приклад 2)

#### 1. Порівняння `ROW_NUMBER`, `RANK` та `DENSE_RANK`:
```sql
SELECT id, value,
       ROW_NUMBER() OVER (
           PARTITION BY sensor_id
           ORDER BY value DESC, measured_at, id
       ) AS row_no,
       RANK() OVER (
           PARTITION BY sensor_id
           ORDER BY value DESC
       ) AS rank_no,
       DENSE_RANK() OVER (
           PARTITION BY sensor_id
           ORDER BY value DESC
       ) AS dense_no
FROM lab06.readings
WHERE sensor_id = 1
ORDER BY value DESC, measured_at, id;
```

Фактичний результат з журналу:

```text
 id | value | row_no | rank_no | dense_no 
----+-------+--------+---------+----------
  6 |  25.0 |      1 |       1 |        1
  4 |  24.0 |      2 |       2 |        2
  5 |  23.0 |      3 |       3 |        3
  2 |  22.0 |      4 |       4 |        4
  3 |  22.0 |      5 |       4 |        4
  1 |  20.0 |      6 |       6 |        5
(6 rows)
```

Записи `id = 2` та `3` мають однакову температуру $22.0^\circ\text{C}$ і ділять 4-й ранг. Після них `RANK()` переходить одразу до рангу 6 (наявний пропуск рангу 5), тоді як `DENSE_RANK()` призначає ранг 5 без пропуску.

#### 2. Самостійна перевірка 2: Додавання `id` в `ORDER BY` ранжування:
```sql
SELECT id, value,
       RANK() OVER (
           PARTITION BY sensor_id
           ORDER BY value DESC, id
       ) AS rank_no_with_id,
       DENSE_RANK() OVER (
           PARTITION BY sensor_id
           ORDER BY value DESC, id
       ) AS dense_no_with_id
FROM lab06.readings
WHERE sensor_id = 1
ORDER BY value DESC, id;
```

Фактичний результат:

```text
 id | value | rank_no_with_id | dense_no_with_id 
----+-------+-----------------+------------------
  6 |  25.0 |               1 |                1
  4 |  24.0 |               2 |                2
  5 |  23.0 |               3 |                3
  2 |  22.0 |               4 |                4
  3 |  22.0 |               5 |                5
  1 |  20.0 |               6 |                6
(6 rows)
```

Через унікальність пари `(value, id)` збіги ліквідовано: записи розділили 4-е і 5-е місця, що нівелювало логіку однакового рангу.

---

### 3.6. Сусідні вимірювання та обчислення дельти (Приклад 3)

#### 1. Порівняння через іменоване вікно `WINDOW w`:
```sql
SELECT id, measured_at, value,
       LAG(value) OVER w AS prev_value,
       LEAD(value) OVER w AS next_value,
       value - LAG(value) OVER w AS delta
FROM lab06.readings
WHERE sensor_id = 1
WINDOW w AS (
    PARTITION BY sensor_id
    ORDER BY measured_at, id
)
ORDER BY measured_at, id;
```

Фактичний результат з журналу:

```text
 id |     measured_at     | value | prev_value | next_value | delta 
----+---------------------+-------+------------+------------+-------
  1 | 2026-10-01 08:00:00 |  20.0 |            |       22.0 |      
  2 | 2026-10-01 08:10:00 |  22.0 |       20.0 |       22.0 |   2.0
  3 | 2026-10-01 08:20:00 |  22.0 |       22.0 |       24.0 |   0.0
  4 | 2026-10-01 08:20:00 |  24.0 |       22.0 |       23.0 |   2.0
  5 | 2026-10-01 08:40:00 |  23.0 |       24.0 |       25.0 |  -1.0
  6 | 2026-10-01 08:50:00 |  25.0 |       23.0 |            |   2.0
(6 rows)
```

Перший рядок коректно повернув `prev_value = NULL` та `delta = NULL`. Для записів з однаковим часом 08:20 тай-брейкер `id` визначив, що для `id = 4` попередником є `id = 3` ($\Delta = 2.0^\circ\text{C}$).

#### 2. Самостійна перевірка 3: Зсув на 2 позиції назад (`LAG(value, 2)`):
```sql
SELECT id, measured_at, value,
       LAG(value, 2) OVER w AS prev_2_value,
       value - LAG(value, 2) OVER w AS delta_2
FROM lab06.readings
WHERE sensor_id = 1
WINDOW w AS (
    PARTITION BY sensor_id
    ORDER BY measured_at, id
)
ORDER BY measured_at, id;
```

Фактичний результат:

```text
 id |     measured_at     | value | prev_2_value | delta_2 
----+---------------------+-------+--------------+---------
  1 | 2026-10-01 08:00:00 |  20.0 |              |        
  2 | 2026-10-01 08:10:00 |  22.0 |              |        
  3 | 2026-10-01 08:20:00 |  22.0 |         20.0 |     2.0
  4 | 2026-10-01 08:20:00 |  24.0 |         22.0 |     2.0
  5 | 2026-10-01 08:40:00 |  23.0 |         22.0 |     1.0
  6 | 2026-10-01 08:50:00 |  25.0 |         24.0 |     1.0
(6 rows)
```

Перші два записи не мають сусідів зі зсувом 2, тому отримують `NULL`.

---

### 3.7. Накопичувальні показники та підрахунок подій (Приклад 4)

#### 1. Розрахунок кумулятивних метрик для датчика 1 (`T-01`):
```sql
SELECT r.id, r.measured_at, r.value,
       COUNT(*) OVER w AS running_count,
       ROUND(AVG(r.value) OVER w, 2) AS running_avg,
       SUM(CASE WHEN r.value > s.limit_value
                THEN 1 ELSE 0 END) OVER w AS over_count
FROM lab06.readings AS r
JOIN lab06.sensors AS s ON s.id = r.sensor_id
WHERE r.sensor_id = 1
WINDOW w AS (
    PARTITION BY r.sensor_id
    ORDER BY r.measured_at, r.id
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
)
ORDER BY r.measured_at, r.id;
```

Фактичний результат з журналу:

```text
 id |     measured_at     | value | running_count | running_avg | over_count 
----+---------------------+-------+---------------+-------------+------------
  1 | 2026-10-01 08:00:00 |  20.0 |             1 |       20.00 |          0
  2 | 2026-10-01 08:10:00 |  22.0 |             2 |       21.00 |          0
  3 | 2026-10-01 08:20:00 |  22.0 |             3 |       21.33 |          0
  4 | 2026-10-01 08:20:00 |  24.0 |             4 |       22.00 |          1
  5 | 2026-10-01 08:40:00 |  23.0 |             5 |       22.20 |          2
  6 | 2026-10-01 08:50:00 |  25.0 |             6 |       22.67 |          3
(6 rows)
```

Значення $22.0^\circ\text{C}$ не збільшує `over_count`, оскільки умова сувора ($> 22.0$). Перше перевищення виникає для `id = 4` ($24.0^\circ\text{C}$).

#### 2. Самостійна перевірка 4: Розрахунок для датчика 2 (`T-02`, ліміт 30.0):
```sql
SELECT r.id, r.measured_at, r.value,
       COUNT(*) OVER w AS running_count,
       ROUND(AVG(r.value) OVER w, 2) AS running_avg,
       SUM(CASE WHEN r.value > s.limit_value
                THEN 1 ELSE 0 END) OVER w AS over_count
FROM lab06.readings AS r
JOIN lab06.sensors AS s ON s.id = r.sensor_id
WHERE r.sensor_id = 2
WINDOW w AS (
    PARTITION BY r.sensor_id
    ORDER BY r.measured_at, r.id
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
)
ORDER BY r.measured_at, r.id;
```

Фактичний результат:

```text
 id |     measured_at     | value | running_count | running_avg | over_count 
----+---------------------+-------+---------------+-------------+------------
  7 | 2026-10-01 08:00:00 |  28.0 |             1 |       28.00 |          0
  8 | 2026-10-01 08:10:00 |  29.0 |             2 |       28.50 |          0
  9 | 2026-10-01 08:20:00 |  31.0 |             3 |       29.33 |          1
 10 | 2026-10-01 08:30:00 |  31.0 |             4 |       29.75 |          2
 11 | 2026-10-01 08:40:00 |  30.0 |             5 |       29.80 |          2
 12 | 2026-10-01 08:50:00 |  29.0 |             6 |       29.67 |          2
(6 rows)
```

Фінальний стан: 6 показів, середнє $29.67^\circ\text{C}$ та 2 перевищення порогу.

---

### 3.8. Порівняння поведінки `ROWS` та `RANGE` (Приклад 5)

```sql
SELECT id, measured_at, value,
       COUNT(*) OVER (
           PARTITION BY sensor_id
           ORDER BY measured_at, id
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS rows_count,
       COUNT(*) OVER (
           PARTITION BY sensor_id
           ORDER BY measured_at
           RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS range_count
FROM lab06.readings
WHERE sensor_id = 1
ORDER BY measured_at, id;
```

Фактичний результат з журналу:

```text
 id |     measured_at     | value | rows_count | range_count 
----+---------------------+-------+------------+-------------
  1 | 2026-10-01 08:00:00 |  20.0 |          1 |           1
  2 | 2026-10-01 08:10:00 |  22.0 |          2 |           2
  3 | 2026-10-01 08:20:00 |  22.0 |          3 |           4
  4 | 2026-10-01 08:20:00 |  24.0 |          4 |           4
  5 | 2026-10-01 08:40:00 |  23.0 |          5 |           5
  6 | 2026-10-01 08:50:00 |  25.0 |          6 |           6
(6 rows)
```

О 08:20 `rows_count` для `id = 3` дорівнює 3, а `range_count` — 4! `RANGE` оцінює логічне значення мітки і включає обидва записи о 08:20 одночасно.

#### Самостійна перевірка 5: Перевірка рамки за замовчуванням:
```sql
SELECT id, measured_at, value,
       COUNT(*) OVER (
           PARTITION BY sensor_id
           ORDER BY measured_at
       ) AS default_count,
       COUNT(*) OVER (
           PARTITION BY sensor_id
           ORDER BY measured_at
           RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS explicit_range_count
FROM lab06.readings
WHERE sensor_id = 1
ORDER BY measured_at, id;
```

Фактичний результат:

```text
 id |     measured_at     | value | default_count | explicit_range_count 
----+---------------------+-------+---------------+----------------------
  1 | 2026-10-01 08:00:00 |  20.0 |             1 |                    1
  2 | 2026-10-01 08:10:00 |  22.0 |             2 |                    2
  3 | 2026-10-01 08:20:00 |  22.0 |             4 |                    4
  4 | 2026-10-01 08:20:00 |  24.0 |             4 |                    4
  5 | 2026-10-01 08:40:00 |  23.0 |             5 |                    5
  6 | 2026-10-01 08:50:00 |  25.0 |             6 |                    6
(6 rows)
```

Стовпці повністю ідентичні, що доводить дію дефолтного стандарту `RANGE ... CURRENT ROW` у PostgreSQL.

---

### 3.9. Ковзне середнє: кількість рядків проти часового вікна (Приклад 6)

```sql
SELECT id, measured_at, value,
       COUNT(*) OVER w_rows AS n_rows,
       ROUND(AVG(value) OVER w_rows, 2) AS avg_3_rows,
       COUNT(*) OVER w_time AS n_time,
       ROUND(AVG(value) OVER w_time, 2) AS avg_20_min
FROM lab06.readings
WHERE sensor_id = 1
WINDOW
    w_rows AS (
        PARTITION BY sensor_id
        ORDER BY measured_at, id
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ),
    w_time AS (
        PARTITION BY sensor_id
        ORDER BY measured_at
        RANGE BETWEEN INTERVAL '20 minutes' PRECEDING AND CURRENT ROW
    )
ORDER BY measured_at, id;
```

Фактичний результат з журналу:

```text
 id |     measured_at     | value | n_rows | avg_3_rows | n_time | avg_20_min 
----+---------------------+-------+--------+------------+--------+------------
  1 | 2026-10-01 08:00:00 |  20.0 |      1 |      20.00 |      1 |      20.00
  2 | 2026-10-01 08:10:00 |  22.0 |      2 |      21.00 |      2 |      21.00
  3 | 2026-10-01 08:20:00 |  22.0 |      3 |      21.33 |      4 |      22.00
  4 | 2026-10-01 08:20:00 |  24.0 |      3 |      22.67 |      4 |      22.00
  5 | 2026-10-01 08:40:00 |  23.0 |      3 |      23.00 |      3 |      23.00
  6 | 2026-10-01 08:50:00 |  25.0 |      3 |      24.00 |      2 |      24.00
(6 rows)
```

Для `id = 4` (08:20) рамка `ROWS` охоплює 3 записи (сер. 22.67), тоді як часова рамка за 20 хвилин охоплює всі 4 записи від 08:00 до 08:20 (сер. 22.00).

#### Самостійна перевірка 6: Звуження інтервалу до 10 хвилин:
```sql
SELECT id, measured_at, value,
       COUNT(*) OVER w_10min AS n_10min,
       ROUND(AVG(value) OVER w_10min, 2) AS avg_10min
FROM lab06.readings
WHERE sensor_id = 1
WINDOW w_10min AS (
    PARTITION BY sensor_id
    ORDER BY measured_at
    RANGE BETWEEN INTERVAL '10 minutes' PRECEDING AND CURRENT ROW
)
ORDER BY measured_at, id;
```

Фактичний результат:

```text
 id |     measured_at     | value | n_10min | avg_10min 
----+---------------------+-------+---------+-----------
  1 | 2026-10-01 08:00:00 |  20.0 |       1 |     20.00
  2 | 2026-10-01 08:10:00 |  22.0 |       2 |     21.00
  3 | 2026-10-01 08:20:00 |  22.0 |       3 |     22.67
  4 | 2026-10-01 08:20:00 |  24.0 |       3 |     22.67
  5 | 2026-10-01 08:40:00 |  23.0 |       1 |     23.00
  6 | 2026-10-01 08:50:00 |  25.0 |       2 |     24.00
(6 rows)
```

О 08:40 `n_10min = 1`, оскільки попередній показ був зафіксований о 08:20 (20 хвилин тому, що виходить за межі 10-хвилинного вікна).

---

### 3.10. Крайні значення та подолання пастки `LAST_VALUE` (Приклад 7)

```sql
SELECT id, measured_at, value,
       FIRST_VALUE(value) OVER w_full AS first_value,
       LAST_VALUE(value) OVER (
           PARTITION BY sensor_id
           ORDER BY measured_at, id
       ) AS last_default,
       LAST_VALUE(value) OVER w_full AS last_full
FROM lab06.readings
WHERE sensor_id = 1
WINDOW w_full AS (
    PARTITION BY sensor_id
    ORDER BY measured_at, id
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
)
ORDER BY measured_at, id;
```

Фактичний результат з журналу:

```text
 id |     measured_at     | value | first_value | last_default | last_full 
----+---------------------+-------+-------------+--------------+-----------
  1 | 2026-10-01 08:00:00 |  20.0 |        20.0 |         20.0 |      25.0
  2 | 2026-10-01 08:10:00 |  22.0 |        20.0 |         22.0 |      25.0
  3 | 2026-10-01 08:20:00 |  22.0 |        20.0 |         22.0 |      25.0
  4 | 2026-10-01 08:20:00 |  24.0 |        20.0 |         24.0 |      25.0
  5 | 2026-10-01 08:40:00 |  23.0 |        20.0 |         23.0 |      25.0
  6 | 2026-10-01 08:50:00 |  25.0 |        20.0 |         25.0 |      25.0
(6 rows)
```

Стовпець `last_default` у кожному рядку дублює `value`, оскільки дефолтна рамка закінчується на `CURRENT ROW`. Розширена рамка `w_full` коректно повертає фінальне значення 25.0 у кожному рядку.

#### Самостійна перевірка 7: Останнє та максимальне значення для T-02:
```sql
SELECT DISTINCT
       LAST_VALUE(value) OVER (
           PARTITION BY sensor_id
           ORDER BY measured_at, id
           ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
       ) AS last_sensor_value,
       MAX(value) OVER (
           PARTITION BY sensor_id
       ) AS max_sensor_value
FROM lab06.readings
WHERE sensor_id = 2;
```

Фактичний результат:

```text
 last_sensor_value | max_sensor_value 
-------------------+------------------
              29.0 |             31.0
(1 row)
```

Останнє значення ($29.0^\circ\text{C}$ о 08:50) відрізняється від абсолютного максимуму датчика ($31.0^\circ\text{C}$).

---

### 3.11. Останній стан сутностей через CTE (Приклад 8)

```sql
WITH numbered AS (
    SELECT id, sensor_id, measured_at, value,
           ROW_NUMBER() OVER (
               PARTITION BY sensor_id
               ORDER BY measured_at DESC, id DESC
           ) AS rn
    FROM lab06.readings
)
SELECT sensor_id, id, measured_at, value
FROM numbered
WHERE rn = 1
ORDER BY sensor_id;
```

Фактичний результат з журналу:

```text
 sensor_id | id |     measured_at     | value 
-----------+----+---------------------+-------
         1 |  6 | 2026-10-01 08:50:00 |  25.0
         2 | 12 | 2026-10-01 08:50:00 |  29.0
         3 | 18 | 2026-10-01 08:50:00 |  20.0
(3 rows)
```

Отримано рівно по одному найновішому запису для кожного датчика.

#### Самостійна перевірка 8: Отримання двох останніх показів (`rn <= 2`):
```sql
WITH numbered AS (
    SELECT id, sensor_id, measured_at, value,
           ROW_NUMBER() OVER (
               PARTITION BY sensor_id
               ORDER BY measured_at DESC, id DESC
           ) AS rn
    FROM lab06.readings
)
SELECT sensor_id, id, measured_at, value, rn
FROM numbered
WHERE rn <= 2
ORDER BY sensor_id, measured_at DESC, id DESC;
```

Фактичний результат: виведено рівно 6 рядків (по 2 останні записи на кожен датчик).

---

### 3.12. Ланцюжок CTE для виявлення стрибків температури (Приклад 9)

```sql
WITH previous AS (
    SELECT id, sensor_id, measured_at, value,
           LAG(value) OVER (
               PARTITION BY sensor_id
               ORDER BY measured_at, id
           ) AS prev_value
    FROM lab06.readings
), changes AS (
    SELECT id, sensor_id, measured_at,
           value, prev_value,
           value - prev_value AS delta
    FROM previous
)
SELECT sensor_id, id, measured_at,
       prev_value, value, delta
FROM changes
WHERE ABS(delta) >= 2.0
ORDER BY sensor_id, measured_at, id;
```

Фактичний результат з журналу:

```text
 sensor_id | id |     measured_at     | prev_value | value | delta 
-----------+----+---------------------+------------+-------+-------
         1 |  2 | 2026-10-01 08:10:00 |       20.0 |  22.0 |   2.0
         1 |  4 | 2026-10-01 08:20:00 |       22.0 |  24.0 |   2.0
         1 |  6 | 2026-10-01 08:50:00 |       23.0 |  25.0 |   2.0
         2 |  9 | 2026-10-01 08:20:00 |       29.0 |  31.0 |   2.0
         3 | 16 | 2026-10-01 08:30:00 |       19.0 |  17.0 |  -2.0
         3 | 18 | 2026-10-01 08:50:00 |       18.0 |  20.0 |   2.0
(6 rows)
```

Знайдено 6 подій різких коливань, серед яких `id = 16` є стрибком охолодження (дельта $-2.0^\circ\text{C}$).  
*У самостійній перевірці 9 при фільтрації `delta >= 2.0` запис 16 відсіявся, залишивши рівно 5 рядків нагріву.*

---

### 3.13. Рекурсивні запити обходу дерева обладнання (Приклади 10 та 11)

#### 1. Повне дерево обладнання з відступами та захистом від циклів:
```sql
WITH RECURSIVE tree AS (
    SELECT id, parent_id, name,
           0 AS depth,
           ARRAY[id] AS path
    FROM lab06.equipment
    WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.parent_id, e.name,
           t.depth + 1,
           t.path || e.id
    FROM lab06.equipment AS e
    JOIN tree AS t ON e.parent_id = t.id
    WHERE NOT (e.id = ANY(t.path))
)
SELECT id, depth, path,
       repeat('    ', depth) || name AS equipment_tree
FROM tree
ORDER BY path;
```

Фактичний результат з журналу:

```text
 id | depth |  path   |        equipment_tree        
----+-------+---------+------------------------------
  1 |     0 | {1}     | Навчальна лабораторія
  2 |     1 | {1,2}   |     Стенд А
  4 |     2 | {1,2,4} |         Нагрівальна камера
  5 |     2 | {1,2,5} |         Охолоджувальний блок
  3 |     1 | {1,3}   |     Стенд Б
  6 |     2 | {1,3,6} |         Повітряний канал
(6 rows)
```

#### 2. Рекурсивний пошук датчиків для Стенда А (`id = 2`):
```sql
WITH RECURSIVE branch AS (
    SELECT id, ARRAY[id] AS path
    FROM lab06.equipment
    WHERE id = 2
    UNION ALL
    SELECT e.id, b.path || e.id
    FROM lab06.equipment AS e
    JOIN branch AS b ON e.parent_id = b.id
    WHERE NOT (e.id = ANY(b.path))
)
SELECT s.id AS sensor_id, s.sensor_code,
       e.name AS equipment_name
FROM branch AS b
JOIN lab06.equipment AS e ON e.id = b.id
JOIN lab06.sensors AS s ON s.equipment_id = b.id
ORDER BY s.id;
```

Фактичний результат:

```text
 sensor_id | sensor_code |    equipment_name    
-----------+-------------+----------------------
         1 | T-01        | Нагрівальна камера
         2 | T-02        | Охолоджувальний блок
(2 rows)
```

Рекурсія охопила всі дочірні вузли Стенда А і знайшла обидва датчики.  
*У самостійній перевірці 11 Стенд Б повернув `T-03`, а запуск від кореня лабораторії (id = 1) повернув усі три сенсори.*

---

### 3.14. Дослідження `VIEW`, `MATERIALIZED VIEW` та життєвого циклу `REFRESH` (Приклади 12–14)

#### 1. Створення звичайного представлення `v_sensor_summary`:
```sql
CREATE OR REPLACE VIEW lab06.v_sensor_summary AS
SELECT s.id AS sensor_id,
       s.sensor_code,
       COUNT(r.id) AS reading_count,
       ROUND(AVG(r.value), 2) AS avg_value,
       MAX(r.value) AS max_value,
       COUNT(r.id) FILTER (
           WHERE r.value > s.limit_value
       ) AS over_limit_count,
       MAX(r.measured_at) AS last_measured_at
FROM lab06.sensors AS s
LEFT JOIN lab06.readings AS r ON r.sensor_id = s.id
GROUP BY s.id, s.sensor_code;
```

Результат вибірки:

```text
 sensor_code | reading_count | avg_value | max_value | over_limit_count 
-------------+---------------+-----------+-----------+------------------
 T-01        |             6 |     22.67 |      25.0 |                3
 T-02        |             6 |     29.67 |      31.0 |                2
 T-03        |             6 |     18.33 |      20.0 |                1
(3 rows)
```

#### 2. Створення `MATERIALIZED VIEW` та проведення експерименту `REFRESH`:

- **Крок 1:** Додавання контрольного показу `id = 9001` ($32.0^\circ\text{C}$):
  ```sql
  INSERT INTO lab06.readings (id, sensor_id, measured_at, value)
  VALUES (9001, 1, '2026-10-01 09:00', 32.0);
  ```
- **Крок 2:** Звірка до `REFRESH`:
  ```text
        source       | reading_count | avg_value | max_value | over_limit_count 
  -------------------+---------------+-----------+-----------+------------------
   MATERIALIZED VIEW |             6 |     22.67 |      25.0 |                3
   VIEW              |             7 |     24.00 |      32.0 |                4
  (2 rows)
  ```
  `VIEW` миттєво відобразило новий показ, тоді як `MATERIALIZED VIEW` зберегло старий результат.
- **Крок 3:** Виконання `REFRESH MATERIALIZED VIEW lab06.mv_sensor_summary;`:
  ```text
        source       | reading_count | avg_value | max_value | over_limit_count 
  -------------------+---------------+-----------+-----------+------------------
   MATERIALIZED VIEW |             7 |     24.00 |      32.0 |                4
   VIEW              |             7 |     24.00 |      32.0 |                4
  (2 rows)
  ```
  Після виклику `REFRESH` дані синхронізувалися.
- **Крок 4:** Видалення запису `9001` та повторний `REFRESH`: обидва джерела коректно повернулися до вихідних 6 показів і середнього $22.67^\circ\text{C}$.

---

### 3.15. Творче завдання: Система виявлення теплових аномалій (Розділ 9)

#### 1. Постановка власного правила:
- **Назва правила:** Критична теплова аномалія стенда (Critical Thermal Anomaly).
- **Критерії:**
  1. Поточна температура вища за ліміт: $V > \text{limit\_value}$.
  2. Попереднє вимірювання також перевищувало ліміт: $\text{prev\_val} > \text{limit\_value}$ (стійкий перегрів).
  3. Відбувся стрибок температури: $\Delta = V - \text{prev\_val} \ge 1.0^\circ\text{C}$.
  4. Поточна температура вища за ковзне середнє трьох останніх вимірювань: $V > \text{moving\_avg\_3}$.
- **Дія для оператора:** Аварійна зупинка стенда та аудит системи охолодження.

#### 2. DDL/DML розширення даних:
Створено новий вузол обладнання `id = 7` (під Стендом А `parent_id = 2`), новий сенсор `T-04` (`id = 4`, ліміт $25.0^\circ\text{C}$) та 8 вимірювань (ідентифікатори 101–108):

```sql
BEGIN;
INSERT INTO lab06.equipment (id, parent_id, name)
VALUES (7, 2, 'Експериментальний модуль нагріву');

INSERT INTO lab06.sensors (id, sensor_code, equipment_id, limit_value)
VALUES (4, 'T-04', 7, 25.0);

INSERT INTO lab06.readings (id, sensor_id, measured_at, value) VALUES
    (101, 4, '2026-10-01 08:00', 23.0),
    (102, 4, '2026-10-01 08:10', 25.0),
    (103, 4, '2026-10-01 08:20', 26.5),
    (104, 4, '2026-10-01 08:30', 28.0),
    (105, 4, '2026-10-01 08:40', 28.5),
    (106, 4, '2026-10-01 08:40', 27.0),
    (107, 4, '2026-10-01 08:50', 24.0),
    (108, 4, '2026-10-01 09:00', 29.0);
COMMIT;
```

#### 3. Комплексний аналітичний запит та створення двох представлень:
Запит об'єднує:
- `WITH RECURSIVE` для включення всіх підвузлів Стенда А (включно з новим модулем 7).
- `LAG()` з розрахунком $\Delta$.
- Віконну рамку `ROWS BETWEEN 2 PRECEDING AND CURRENT ROW` для ковзного середнього.
- Звичайний CTE логічної оцінки критеріїв.
- `DENSE_RANK()` для ранжування стрибків нагріву.

```sql
CREATE OR REPLACE VIEW lab06.v_thermal_anomalies AS
WITH RECURSIVE stand_equipment AS (
    SELECT id, ARRAY[id] AS path
    FROM lab06.equipment
    WHERE id = 2

    UNION ALL

    SELECT e.id, se.path || e.id
    FROM lab06.equipment AS e
    JOIN stand_equipment AS se ON e.parent_id = se.id
    WHERE NOT (e.id = ANY(se.path))
), stand_sensors AS (
    SELECT s.id AS sensor_id, s.sensor_code, s.limit_value, e.name AS equipment_name
    FROM stand_equipment se
    JOIN lab06.equipment e ON e.id = se.id
    JOIN lab06.sensors s ON s.equipment_id = se.id
), metrics AS (
    SELECT r.id, r.sensor_id, ss.sensor_code, ss.equipment_name,
           r.measured_at, r.value, ss.limit_value,
           LAG(r.value) OVER w AS prev_value,
           ROUND(r.value - LAG(r.value) OVER w, 2) AS delta,
           ROUND(AVG(r.value) OVER w_mov, 2) AS moving_avg_3
    FROM lab06.readings r
    JOIN stand_sensors ss ON ss.sensor_id = r.sensor_id
    WINDOW
        w AS (
            PARTITION BY r.sensor_id
            ORDER BY r.measured_at, r.id
        ),
        w_mov AS (
            PARTITION BY r.sensor_id
            ORDER BY r.measured_at, r.id
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        )
), evaluated AS (
    SELECT m.*,
           CASE
               WHEN m.value > m.limit_value
                AND m.prev_value > m.limit_value
                AND m.delta >= 1.0
                AND m.value > m.moving_avg_3
               THEN 'CRITICAL_ANOMALY'
               ELSE 'NORMAL'
           END AS anomaly_status
    FROM metrics m
)
SELECT sensor_code, equipment_name, id AS reading_id,
       measured_at, value, limit_value, prev_value, delta,
       moving_avg_3, anomaly_status,
       DENSE_RANK() OVER (
           PARTITION BY sensor_code
           ORDER BY delta DESC NULLS LAST
       ) AS rank_by_spike
FROM evaluated
ORDER BY sensor_code, measured_at, reading_id;

CREATE MATERIALIZED VIEW lab06.mv_thermal_anomalies AS
SELECT * FROM lab06.v_thermal_anomalies;
```

#### 4. Таблиця верифікації трьох контрольних випадків:
```sql
SELECT reading_id, sensor_code, measured_at, value, prev_value, delta, moving_avg_3, anomaly_status
FROM lab06.v_thermal_anomalies
WHERE sensor_code = 'T-04' AND reading_id IN (102, 104, 105)
ORDER BY reading_id;
```

Фактичний результат з журналу:

```text
 reading_id | sensor_code |     measured_at     | value | prev_value | delta | moving_avg_3 |  anomaly_status  
------------+-------------+---------------------+-------+------------+-------+--------------+------------------
        102 | T-04        | 2026-10-01 08:10:00 |  25.0 |       23.0 |  2.00 |        24.00 | NORMAL
        104 | T-04        | 2026-10-01 08:30:00 |  28.0 |       26.5 |  1.50 |        26.50 | CRITICAL_ANOMALY
        105 | T-04        | 2026-10-01 08:40:00 |  28.5 |       28.0 |  0.50 |        27.67 | NORMAL
(3 rows)
```

| Випадок | Запис | Передбачено | Отримано фактично | Висновок |
| :--- | :--- | :--- | :--- | :--- |
| **Умова виконується** | `id = 104` ($28.0^\circ\text{C}$) | Статус `CRITICAL_ANOMALY` | `CRITICAL_ANOMALY` ($28 > 25$, $26.5 > 25$, $\Delta = 1.5 \ge 1.0$) | Правило успішно зафіксувало стійкий критичний перегрів зі стрибком |
| **Умова не виконується** | `id = 105` ($28.5^\circ\text{C}$) | Статус `NORMAL` | `NORMAL` ($\Delta = 0.5 < 1.0$) | Стрибок менший за поріг $\ge 1.0^\circ\text{C}$, аварія не оголошується |
| **Граничний випадок** | `id = 102` ($25.0^\circ\text{C}$) | Статус `NORMAL` | `NORMAL` ($25.0 \ngtr 25.0$) | Рівність порогу не вважається перевищенням |

#### 5. Триетапна валідація оновлення `REFRESH` для власного звіту:
1. **Стан 1 (До зміни):** В `mv_thermal_anomalies` зафіксовано рівно 1 аномалію та 7 нормальних записів.
2. **Стан 2 (Після додавання аномального запису 109 до REFRESH):**
   ```text
           src        | count 
   -------------------+-------
    VIEW              |     2
    MATERIALIZED VIEW |     1
   (2 rows)
   ```
   У `VIEW` кількість аномалій зросла до 2, а в `MATERIALIZED VIEW` збереглося старе число 1.
3. **Стан 3 (Після REFRESH):**
   ```text
           src        | count 
   -------------------+-------
    VIEW              |     2
    MATERIALIZED VIEW |     2
   (2 rows)
   ```
   Обидва представлення синхронізовані на значенні 2. Після видалення запису 109 та повторного `REFRESH` збережений стан повернувся до вихідного (1 аномалія).

---

## 4. Відповіді на контрольні питання

| № | Контрольне питання | Вичерпна технічна відповідь |
|---|---|---|
| 1 | **Чому `GROUP BY sensor_id` дає 3 рядки, а `AVG(value) OVER (PARTITION BY sensor_id)` — 18?** | Оператор `GROUP BY` групує вхідний набір кортежів за заданим ключем і схлопує (згортає) їх, повертаючи рівно один агрегований рядок на кожну унікальну групу (втрачаючи деталізацію окремих вимірювань). Віконна функція з клаузою `OVER` проводить агрегацію над розділом рядків без схлопування вибірки: вона додає обчислене контекстне значення до кожного з 18 вихідних рядків, зберігаючи всі первинні стовпці та часові мітки. |
| 2 | **Коли до `ORDER BY` потрібно додати `id`, а коли це змінить зміст рангу?** | Додавання унікального стовпця `id` є необхідним для детермінації послідовності однакових за часом подій (наприклад, для функцій `ROW_NUMBER()`, `LAG()` або `LEAD()`, щоб однозначно визначити попередника/наступника при збігу міток `08:20`). Навпаки, у функціях `RANK()` та `DENSE_RANK()` додавання `id` змінює фізичний зміст ранжування: пари `(value, id)` стають унікальними, через що рядки з однаковою температурою втрачають спільний ранг і отримують штучну послідовну нумерацію. |
| 3 | **Чому два рядки з часом `08:20` мають однаковий `range_count`, але різний `rows_count`?** | Рамка `ROWS` оперує суто фізичною порядковою позицією рядка у впорядкованому списку: перший рядок з часом `08:20` є третім за порядком (`rows_count = 3`), а другий — четвертим (`rows_count = 4`). Рамка `RANGE` спирається на логічне значення стовпця сортування `measured_at`: оскільки для обох рядків виконується умова $\text{час} \le 08:20$, рамка охоплює всі рядки, що розділяють це значення (обидва записи з часом 08:20), тому `range_count` для обох дорівнює 4. |
| 4 | **Чому рамка з трьох записів не завжди дорівнює часовому інтервалу у двадцять хвилин?** | Рамка `ROWS BETWEEN 2 PRECEDING AND CURRENT ROW` фіксує рівно 3 фізичні кортежі незалежно від реального часу їх фіксації (інтервал між ними може становити 10 секунд або 5 днів). Рамка `RANGE BETWEEN INTERVAL '20 minutes' PRECEDING AND CURRENT ROW` відбирає лише ті вимірювання, часова мітка яких потрапляє в проміжок $[t - 20\text{ хв}, t]$. При нерівномірному надходженні даних у такий інтервал може потрапити як 1 показ (при пропуску зв'язку), так і 4 покази (якщо були повторні вимірювання). |
| 5 | **Чому `LAST_VALUE` без повної рамки не показує останній показ усього датчика?** | За наявності `ORDER BY` у клаузі `OVER` стандартною рамкою за замовчуванням є `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`. Ця рамка динамічно закінчується на поточному рядку, тому `LAST_VALUE()` просто повертає значення поточного кортежу. Щоб отримати істинне фінальне значення всього розділу датчика, необхідно явно розширити межу рамки до кінця: `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING`. |
| 6 | **Що зміниться, якщо відфільтрувати рядки перед `LAG` замість відбору після обчислення `delta`?** | Якщо відсіяти рядки через `WHERE` до виконання віконної функції (наприклад, залишити тільки покази $> 22^\circ\text{C}$), функція `LAG()` шукатиме попередника виключно серед відфільтрованої підмножини. Як наслідок, різниця $\Delta$ розраховуватиметься відносно випадкового попереднього гарячого показу, а не відносно безпосередньо попереднього вимірювання в реальному часі, що спотворить аналіз фізичної швидкості зміни температури. |
| 7 | **Які рядки задає початкова частина рекурсивного CTE і коли обхід завершується?** | Початкова (якірна) частина задає базис індукції — вихідний набір рядків, з якого починається рух по графу (наприклад, корінь дерева з `parent_id IS NULL` або стартовий стенд). Рекурсивний крок ітеративно виконує `JOIN` попереднього кроку з дочірніми вузлами. Обхід автоматично завершується тоді, коли чергова ітерація з'єднання повертає порожній набір рядків (немає нових дочірніх вузлів). |
| 8 | **Чому зміни `readings` видно у `VIEW`, але вони не змінюють `MATERIALIZED VIEW` без `REFRESH`?** | `VIEW` — це динамічний збережений макрос-запит; при кожному зверненні до нього СУБД наново виконує визначальний SQL-запит над поточним станом базових таблиць транзакції. `MATERIALIZED VIEW` — це фізично матеріалізована таблиця на диску; після створення її вміст залишається незмінним до явного виклику команди `REFRESH MATERIALIZED VIEW`, яка блокує представлення та перезаписує збережений знімок актуальними даними. |

---

## 5. Висновки

У процесі виконання лабораторної роботи № 6 було досягнуто таких технічних та інженерних результатів:

1. **Опанування апарату віконних функцій PostgreSQL:** Досліджено використання аналітичних функцій з клаузою `OVER (PARTITION BY ... ORDER BY ...)` для комплексного аналізу часових рядів температури, що дозволило зберегти повну деталізацію всіх 18 первинних вимірювань і одночасно розрахувати контекстні середні та відхилення від максимуму.
2. **Диференціація алгоритмів ранжування:** На практиці вивчено різницю між функціями `ROW_NUMBER()`, `RANK()` та `DENSE_RANK()`. Доведено, що включення унікального первинного ключа `id` в `ORDER BY` ліквідує спільний ранг для однакових температур ($22.0^\circ\text{C}$), перетворюючи ранжування на штучну нумерацію.
3. **Аналіз часової динаміки через `LAG`/`LEAD`:** Реалізовано обчислення динамічних стрибків нагріву та охолодження за допомогою іменованих вікон `WINDOW w`. Доведено фізичну неприпустимість підстановки 0 замість `NULL` для початкових записів через спотворення сенсу дельти.
4. **Дослідження рамок вікна (`ROWS` проти `RANGE`):** На прикладі однакових часових міток `08:20` продемонстровано розбіжність між фізичною позицією рядка у вікні (`rows_count = 3` та `4`) та логічним діапазоном значень (`range_count = 4` для обох). Досліджено дефолтну поведінку PostgreSQL та пастку функції `LAST_VALUE()`, яку успішно вирішено рамкою `UNBOUNDED FOLLOWING`.
5. **Декомпозиція запитів через звичайні та рекурсивні CTE:** Реалізовано ланцюжки CTE для подолання синтаксичної заборони віконних функцій у `WHERE`. Побудовано рекурсивний запит `WITH RECURSIVE` для обходу ієрархії випробувальних стендів та дочірніх датчиків із захистом від циклічних посилань за допомогою масиву шляху `path` та оператора `ANY()`.
6. **Оптимізація та життєвий цикл представлень:** Створено динамічне `VIEW` та збережене `MATERIALIZED VIEW`. Проведено експеримент життєвого циклу `REFRESH`, що наочно продемонстрував розсинхронізацію даних між живим запитом і статичним дисковим знімком та підтвердив необхідність контрольованої процедури оновлення.
7. **Реалізація творчого завдання та інженерна культура:** Розроблено багатокроковий алгоритм виявлення критичних теплових аномалій (комбінація ліміту, стійкості перегріву, ковзного середнього за 3 вимірюваннями та ранжування стрибків). Рішення верифіковано на трьох контрольних випадках (спрацювання, відсутність події, граничний стан). Дотримано вимог ізоляції схеми `lab06` без використання антипатерну мутації `search_path`.
