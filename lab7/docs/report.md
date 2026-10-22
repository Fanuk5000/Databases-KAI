# Лабораторна робота № 7: Функції, процедури, тригери та користувацькі агрегати в PostgreSQL

**Дисципліна:** Бази даних  
**Користувач БД:** `illia`  
**База даних:** `lab6`  
**Схема БД:** `lab07_pr`  
**Інфраструктура:** Docker Container (`postgres_db`, мережа `db_network`)  
**Клієнтське середовище:** CLI-клієнт `psql` (PostgreSQL 17.11)  

---

## 1. Мета роботи

1. Опанувати серверне програмування в СУБД PostgreSQL: навчитися проєктувати та реалізовувати логіку обробки даних за допомогою функцій мовами SQL і PL/pgSQL, процедур, тригерів та користувацьких агрегатів.
2. Дослідити архітектурну різницю між чотирма основними серверними механізмами, навчитися вибирати оптимальний інструмент під конкретну прикладну задачу та пояснювати принципову різницю способів виклику `SELECT` та `CALL`.
3. Засвоїти класифікацію мінливості функцій (`IMMUTABLE`, `STABLE`, `VOLATILE`) та практичний вплив модифікатора `STRICT` на оптимізацію виконання запитів.
4. Опанувати синтаксис та внутрішню анатомію блоку PL/pgSQL: оголошення локальних змінних (`DECLARE`), безпечне присвоєння, типи прив'язки `%TYPE` та `%ROWTYPE`, оператори розгалуження (`IF / ELSIF / ELSE`), вибірку в змінні (`SELECT ... INTO`) та перевірку системної булевої змінної `FOUND`.
5. Дослідити транзакційну поведінку захищених блоків та обробку винятків (`EXCEPTION WHEN ... THEN`): довести механізм створення неявних сейвпоінтів та скасування локальних DML-змін невдалої підтранзакції зі збереженням зовнішнього транзакційного контексту.
6. Засвоїти механізм створення збережених процедур із вихідними параметрами (`OUT`), лічильниками модифікованих рядків (`GET DIAGNOSTICS ... ROW_COUNT`) та автономним керуванням межами транзакцій.
7. Дослідити функціонування рядкових тригерів (`FOR EACH ROW`): реалізувати валідацію й нормалізацію рядків через тригер `BEFORE` (`RETURN NEW` / `RETURN NULL`) та структурувати асинхронний аудит змін у форматі JSONB через тригер `AFTER` (`OLD`, `NEW`, `TG_OP`). Довести зв'язок аудиту із загальною транзакцією та його анулювання при `ROLLBACK`.
8. Сконструювати користувацьку агрегатну функцію (`CREATE AGGREGATE`) для обчислення середньозваженої температури, визначити функції переходу стану (`SFUNC`), фінального обчислення (`FINALFUNC`), тип стану (`STYPE`) та початковий стан (`INITCOND`).
9. Розробити власну систему сигналізації «Контроль температури» в межах творчого завдання: розширити реляційну модель, створити функцію аналізу аварійних порогів `sensor_alarm`, захисний тригер перевірки активності обладнання та порівняти аналітичні середні.
10. Дотримуватися стандартів промислової безпеки: забезпечити повну ізоляцію об'єктів у схемі `lab07_pr` без застосування антипатерну мутації параметра `search_path`.

---

## 2. Теоретичні відомості та архітектурний аналіз

### 2.1. Ізоляція схеми та ризики мутації `search_path` (Anti-pattern)

У реляційній СКБД PostgreSQL схема є виділеним простором імен усередині бази даних. Системний параметр `search_path` визначає черговість перегляду схем під час резолюції некваліфікованих імен таблиць чи функцій:

#### Чому `SET search_path` є небезпечним антипатерном:
1. **Волатильність сесії:** Налаштування діє лише в контексті поточного фізичного підключення. При скиданні з'єднання, виконанні запитів через пул транзакцій (PgBouncer, Agroal) або відкритті нової сесії клієнта параметр повертається до значення за замовчуванням (`"$user", public`). Усі наступні звернення зазнають аварійного завершення з помилкою `42P01: relation does not exist`.
2. **Вразливість до перехоплення (Search-path Hijacking):** Відсутність явної схеми дозволяє зловмиснику або сторонньому застосунку створити таблицю чи функцію з ідентичним ім'ям у публічній схемі `public`, перехоплюючи виконання чутливих бізнес-операцій.
3. **Непрозорість аудиту:** У системних журналах СКБД запити без префікса не містять однозначної інформації про те, яка саме версія таблиці брала участь у транзакції.

**Промисловий стандарт:** Повна відмова від сесійного виконання `SET search_path` на користь суворої явної двокомпонентної кваліфікації об'єктів назвою схеми: `lab07_pr.sensors`, `lab07_pr.readings`, `lab07_pr.to_fahrenheit`.

---

### 2.2. Чотири серверні механізми: архітектурне зіставлення

В архітектурі PostgreSQL реалізовано чотири фундаментальні механізми серверної обробки даних, що виконують кардинально різні ролі:

| Механізм | Спосіб виклику | Типове призначення | Транзакційне керування |
|---|---|---|---|
| **SQL- / PL/pgSQL функція** | Виклик у `SELECT`, `WHERE`, `JOIN` | Обчислення та повернення скаляра або реляційної таблиці (`TABLE`) | Працює виключно всередині викликаючого запиту; `COMMIT` / `ROLLBACK` заборонені |
| **Процедура (`PROCEDURE`)** | Окремий оператор `CALL` | Автономна бізнес-дія, маніпуляція даними, повернення через `OUT` | Підтримує автономні `COMMIT` та `ROLLBACK` (якщо викликана поза зовнішньою транзакцією) |
| **Тригер (`TRIGGER`)** | Автоматично при подіях DML (`INSERT`, `UPDATE`, `DELETE`) | Нормалізація вхідного рядка (`BEFORE`), аудит і каскади (`AFTER`) | Виконується строго в контексті транзакції DML; скасовується при її відкаті |
| **Користувацький агрегат** | Агрегатні запити, `GROUP BY`, віконне `OVER` | Згортання множини рядків у єдиний інтегральний показник | Виконується в контексті сканування викликаючого SQL-запиту |

---

### 2.3. Категорії мінливості функцій (Volatility) та модифікатор `STRICT`

Оптимізатор вартісної моделі PostgreSQL спирається на декларовану категорію мінливості для побудови плану виконання:
1. `IMMUTABLE`: Функція є абсолютно детермінованою. Вона не здійснює читання або запису в таблиці БД і завжди повертає тотожний результат для тотожних значень параметрів (наприклад, математична формула конвертації температури). Результат може бути обчислений ще на етапі планування або закешований у функціональних індексах.
2. `STABLE`: Результат залишається незмінним у межах одного сканування таблиці поточного SQL-оператора, але може залежати від вмісту БД або конфігурації поточної сесії (наприклад, читання з таблиці вимірювань `readings` або функція `now()`).
3. `VOLATILE` (за замовчуванням): Результат може змінюватися навіть у межах обробки одного рядка вибірки (наприклад, генератори псевдовипадкових чисел `random()`, вибірки з послідовностей `nextval()`, або будь-які функції, що містять команди модифікації `INSERT`/`UPDATE`).

**Модифікатор `STRICT` (або `RETURNS NULL ON NULL INPUT`):**  
Вказує системі, що при передачі хоча б одного аргументу зі значенням `NULL` тіло функції навіть не викликається — СКБД негайно повертає `NULL`. Це оптимізує ресурси процесора та спрощує код, позбавляючи потреби писати ручні перевірки `IF p_arg IS NULL`.

---

### 2.4. Анатомія блоку програми PL/pgSQL та безпека типів

Базова одиниця коду в процедурній мові PL/pgSQL — це блок:
```sql
[ <<мітка>> ]
[ DECLARE
    оголошення локальних змінних та констант; ]
BEGIN
    виконувані оператори мови;
[ EXCEPTION
    WHEN назва_помилки THEN
        оператори обробки виняткових ситуацій; ]
END;
```

#### Ключові синтаксичні правила:
- **Долар-лапки (`$$` або `$body$`):** Екранують весь блок вихідного коду, усуваючи конфлікти подвійних або одинарних лапок у строкових літералах.
- **Стандартизація префіксів:** Параметри обов'язково маркуються префіксом `p_` (`p_sensor_id`), локальні змінні — префіксом `v_` (`v_latest_val`), що унеможливлює неоднозначність інтерпретатора між іменами змінних та стовпцями таблиць у SQL-запитах.
- **Динамічна типізація (`%TYPE` та `%ROWTYPE`):**  
  - `%TYPE` наслідує тип конкретного стовпця таблиці: `v_val lab07_pr.readings.value%TYPE;`. При зміні масштабу або типу в DDL код залишається працездатним.
  - `%ROWTYPE` створює композитну змінну, структура якої повністю дублює кортеж таблиці: `v_sensor lab07_pr.sensors%ROWTYPE;`.

---

### 2.5. Керування потоком і читання результатів запитів

Усередині процедурного блоку звичайний оператор `SELECT` без цільового збереження заборонений:
- **`SELECT ... INTO`:** Записує отримані значення в скалярні змінні або композитний запис. Якщо вибірка повертає кілька стовпців, їх перелік через кому відповідає змінним після `INTO`.
- **Булева змінна `FOUND`:** Вбудований індикатор стану. Набуває значення `true`, якщо остання команда `SELECT INTO`, `INSERT`, `UPDATE`, `DELETE` або `FETCH` зачепила хоча б один кортеж.
- **`GET DIAGNOSTICS ... ROW_COUNT`:** Зчитує точну кількість рядків, змінених попередньою DML-командою.
- **Ітерація `FOR rec IN SELECT ... LOOP`:** Забезпечує потокову побудкову обробку результуючого набору без необхідності явної ручної ініціалізації курсорів.

---

### 2.6. Механіка захищених блоків та обробка винятків (`EXCEPTION`)

Секція `EXCEPTION` у вкладеному блоці `BEGIN ... END` принципово трансформує поведінку транзакційного рушія:
1. **Неявний сейвпоінт (Savepoint):** Перед початком виконання захищеного блоку ядро PostgreSQL автоматично створює внутрішню точку збереження.
2. **Локальний відкат:** Якщо під час роботи операторів стається виняток (наприклад, порушення обмеження `unique_violation`), PostgreSQL негайно скасовує **виключно ті DML-зміни, які були виконані всередині цього невдалого захищеного блоку**.
3. **Збереження зовнішньої транзакції:** Після локального відкату керування передається у відповідну гілку `WHEN`, дозволяючи додатку зафіксувати помилку в журналі (`execution_log`) та успішно зафіксувати решту операцій зовнішньої транзакції через `COMMIT`.
4. **Невідкатність лічильників `IDENTITY` / `SEQUENCE`:** Навіть при відкаті підтранзакції лічильники генераторів послідовностей не повертаються назад. Це фундаментальна властивість MVCC для запобігання міжсесійних блокувань, внаслідок чого в первинних ключах фіксуються пропуски нумерації.

---

### 2.7. Функції проти Процедур

Починаючи з версії PostgreSQL 11, процедури (`PROCEDURE`) розділені з функціями (`FUNCTION`):
- **Функція:** Викликається як частина виразу (`SELECT func()`). Зобов'язана повертати тип (`RETURNS`). Виконується строго в контексті викликаючого запиту й не може змінювати стан транзакції (команди `COMMIT` та `ROLLBACK` викликають синтаксичну помилку).
- **Процедура:** Викликається автономним оператором `CALL proc()`. Не має результуючого типу `RETURNS`, а всі значення повертає через параметри з модифікатором `OUT` або `INOUT`. Процедура, запущена поза зовнішнім блоком транзакцій, має право самостійно викликати `COMMIT` або `ROLLBACK`, що критично для пакетної обробки мільйонів рядків частинами.

---

### 2.8. Тригерні автомати: `BEFORE` проти `AFTER`

Тригер — це серверний автомат, що викликає процедуру у відповідь на подію DML:
- **`BEFORE` (Рядковий):** Запускається до фізичної модифікації кортежу в таблиці. Призначений для санітизації (нормалізації) даних та попередньої валідації бізнес-правил. Може безпосередньо змінювати значення полів у системній змінній `NEW`. Обов'язково повертає `NEW` (щоб рядок записався) або `NULL` (щоб тихо скасувати операцію для поточного рядка без помилки).
- **`AFTER` (Рядковий):** Запускається після успішної фіксації кортежу в таблиці. Використовується для ведення незалежного аудиту та каскадного оновлення зв'язаних агрегатів. Поля `NEW` є незмінними; значення, що повертає функція, ігнорується СУБД (прийнято повертати `NULL`).
- **Спеціальні змінні:**
  - `TG_OP`: містить текстовий код події (`'INSERT'`, `'UPDATE'`, `'DELETE'`).
  - `OLD`: образ кортежу до операції (доступний в `UPDATE`, `DELETE`).
  - `NEW`: образ кортежу після операції (доступний в `INSERT`, `UPDATE`).
- **Транзакційна цілісність тригерів:** Усі дії рядкових тригерів виконуються в єдиній транзакції з модифікуючим запитом. Якщо користувач викликає `ROLLBACK`, усі записи журналу аудиту, згенеровані AFTER-тригером, повністю анулюються.

---

### 2.9. Анатомія та життєвий цикл користувацького агрегату

Користувацький агрегат реєструється командою `CREATE AGGREGATE` і моделюється як скінченний автомат з акумулятором стану:
```text
               Вхідний потік рядків (value, weight)
                                │
                                ▼
  ┌───────────┐          ┌──────────────┐
  │ INITCOND  │ ───────► │    SFUNC     │ ◄── (черговий рядок)
  │  '{0,0}'  │          │ weighted_step│
  └───────────┘          └──────┬───────┘
                                │ (оновлений стан)
                                ▼
                         ┌──────────────┐
                         │  FINALFUNC   │
                         │weighted_final│
                         └──────┬───────┘
                                │
                                ▼
                   Результат: weighted_avg
```

- **`STYPE`:** Тип даних проміжного накопичувача (наприклад, `numeric[]` — масив з двох чисел: сума добутків $\sum(V \cdot W)$ та сума ваг $\sum W$).
- **`INITCOND`:** Початкова константа стану акумулятора (`'{0,0}'`).
- **`SFUNC` (State Transition Function):** Функція переходу, що викликається для кожного вхідного рядка вибірки, оновлюючи акумулятор.
- **`FINALFUNC` (Final Calculation Function):** Функція завершального розрахунку, яка викликається один раз наприкінці обробки групи над фінальним станом акумулятора для обчислення підсумкового скаляра (ділення суми добутків на суму ваг із захистом від нульового дільника через `NULLIF`).

---

### 2.10. Зведена архітектурна таблиця конструкцій

| Конструкція | Синтаксичний вираз | Основне призначення | Практичний ефект у роботі |
|---|---|---|---|
| **SQL-функція** | `CREATE FUNCTION ... LANGUAGE sql` | Декларативні обчислення, inlining | Переведення температури за формулою у Фаренгейти |
| **PL/pgSQL функція** | `CREATE FUNCTION ... LANGUAGE plpgsql` | Процедурна логіка, розгалуження | Оцінка рівня температури (`temperature_level`) |
| **`RETURNS TABLE`** | `RETURNS TABLE (id bigint, ...)` | Повернення реляційної вибірки | Видача $N$ останніх показів датчика |
| **`SELECT ... INTO`** | `SELECT val INTO v_val FROM ...` | Збереження результату в змінну | Отримання останнього показу сенсора |
| **Булева `FOUND`** | `IF NOT FOUND THEN ...` | Перевірка наявності даних | Обробка ситуації відсутності вимірювань сенсора |
| **`EXCEPTION WHEN`** | `EXCEPTION WHEN unique_violation THEN` | Локальне перехоплення помилки | Сейвпоінт та збереження журналу при дублікатах |
| **`PROCEDURE`** | `CREATE PROCEDURE ... CALL` | Дія зі зміною даних, параметри OUT | Деактивація датчика зі зчитуванням `ROW_COUNT` |
| **`BEFORE` тригер** | `BEFORE INSERT OR UPDATE ... FOR EACH ROW` | Нормалізація рядка до запису | Очищення крайніх пробілів у коментарях через `btrim` |
| **`AFTER` тригер** | `AFTER INSERT OR UPDATE OR DELETE` | Структуроване журналювання | Ведення аудиту знімків рядків у форматі `jsonb` |
| **`CREATE AGGREGATE`** | `CREATE AGGREGATE ... (SFUNC, FINALFUNC)` | Спеціалізована групова агрегація | Розрахунок середньозваженої температури датчиків |

---

## 3. Протокол виконання та аналіз фактичних логів сесії

Усі операції виконано у середовищі контейнера `postgres_db` у базі даних `lab6` під користувачем `illia`. Повний лог команд і відповідей СКБД зафіксовано у файлі [savings.txt](file:///home/mafi2/Projects/DataBase-discipline/lab7/savings.txt).

---

### 3.1. Перевірка середовища сесії та скидання схеми `lab07_pr`

```sql
SHOW search_path;
SELECT current_database(), current_user, pg_backend_pid();
DROP SCHEMA IF EXISTS lab07_pr CASCADE;
```

Фактичний результат з журналу виконання [savings.txt](file:///home/mafi2/Projects/DataBase-discipline/lab7/savings.txt):

```text
SHOW search_path;
   search_path   
-----------------
 "$user", public
(1 row)

SELECT current_database(), current_user, pg_backend_pid();
 current_database | current_user | pg_backend_pid 
------------------+--------------+----------------
 lab6             | illia        |            221
(1 row)

DROP SCHEMA IF EXISTS lab07_pr CASCADE;
DROP SCHEMA
NOTICE:  schema "lab07_pr" does not exist, skipping
```

Параметр `search_path` залишено незмінним. Усі подальші таблиці створюються в схемі `lab07_pr`.

---

### 3.2. Створення схеми, таблиць та індексів (Розділ 1)

```sql
CREATE SCHEMA lab07_pr;

CREATE TABLE lab07_pr.sensors (
    id     integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name   text NOT NULL UNIQUE,
    active boolean NOT NULL DEFAULT true
);

CREATE TABLE lab07_pr.readings (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sensor_id   integer NOT NULL
                REFERENCES lab07_pr.sensors(id) ON DELETE RESTRICT,
    measured_at timestamptz NOT NULL,
    value       numeric(7,2) NOT NULL
                CHECK (value BETWEEN -80 AND 150),
    weight      numeric(7,2) NOT NULL DEFAULT 1
                CHECK (weight > 0),
    note        text,
    UNIQUE (sensor_id, measured_at)
);

CREATE INDEX IF NOT EXISTS idx_readings_sensor_id 
    ON lab07_pr.readings(sensor_id);

CREATE INDEX IF NOT EXISTS idx_readings_sensor_measured 
    ON lab07_pr.readings(sensor_id, measured_at DESC, id DESC);
```

Фактичний результат з журналу виконання [savings.txt](file:///home/mafi2/Projects/DataBase-discipline/lab7/savings.txt):

```text
CREATE SCHEMA
CREATE TABLE
CREATE TABLE
CREATE INDEX
CREATE INDEX
```

Створено таблиці з обмеженнями цілісності (зовнішні ключі, заборона самопосилання) та B-tree індекси для прискорення віконних операцій.

---

### 3.3. Наповнення базовими даними та верифікація (Розділ 2)

```sql
BEGIN;

INSERT INTO lab07_pr.sensors (name) VALUES
    ('Лабораторія А'),
    ('Лабораторія Б'),
    ('Резервний датчик');

INSERT INTO lab07_pr.readings (sensor_id, measured_at, value, weight) VALUES
    (1, '2026-10-01 09:00:00+03', 20, 1),
    (1, '2026-10-01 09:10:00+03', 22, 2),
    (1, '2026-10-01 09:20:00+03', 24, 1),
    (1, '2026-10-01 09:30:00+03', 30, 2),
    (2, '2026-10-01 09:00:00+03', 18, 1),
    (2, '2026-10-01 09:10:00+03', 20, 3),
    (2, '2026-10-01 09:20:00+03', 22, 2);

COMMIT;

SELECT id, sensor_id, measured_at, value, weight, note
FROM lab07_pr.readings
ORDER BY id;
```

Фактичний результат з журналу виконання [savings.txt](file:///home/mafi2/Projects/DataBase-discipline/lab7/savings.txt):

```text
BEGIN
INSERT 0 3
INSERT 0 7
COMMIT
 id | sensor_id |      measured_at       | value | weight | note 
----+-----------+------------------------+-------+--------+------
  1 |         1 | 2026-10-01 09:00:00+03 | 20.00 |   1.00 | 
  2 |         1 | 2026-10-01 09:10:00+03 | 22.00 |   2.00 | 
  3 |         1 | 2026-10-01 09:20:00+03 | 24.00 |   1.00 | 
  4 |         1 | 2026-10-01 09:30:00+03 | 30.00 |   2.00 | 
  5 |         2 | 2026-10-01 09:00:00+03 | 18.00 |   1.00 | 
  6 |         2 | 2026-10-01 09:10:00+03 | 20.00 |   3.00 | 
  7 |         2 | 2026-10-01 09:20:00+03 | 22.00 |   2.00 | 
(7 rows)
```

Базовий набір сформовано: 3 датчики та 7 первинних показів. Усі поля `note` мають значення `NULL`. Датчик 3 залишається без показів.

---

### 3.4. Завдання 1. Створення SQL-функцій

#### 1. Функція переведення температури `to_fahrenheit` (`IMMUTABLE`, `STRICT`):
```sql
CREATE OR REPLACE FUNCTION lab07_pr.to_fahrenheit(
    p_celsius numeric
)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
    SELECT p_celsius * 9.0 / 5.0 + 32;
$$;

SELECT lab07_pr.to_fahrenheit(20) AS fahrenheit_20;
SELECT lab07_pr.to_fahrenheit(NULL) AS fahrenheit_null;
```

Фактичний результат з журналу виконання [savings.txt](file:///home/mafi2/Projects/DataBase-discipline/lab7/savings.txt):

```text
CREATE FUNCTION
 fahrenheit_20 
---------------
         68.00
(1 row)

 fahrenheit_null 
-----------------
          <NULL>
(1 row)
```

#### 2. Функція читання таблиці `average_value` (`STABLE`):
```sql
CREATE OR REPLACE FUNCTION lab07_pr.average_value(
    p_sensor_id integer
)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
    SELECT avg(r.value)
    FROM lab07_pr.readings AS r
    WHERE r.sensor_id = p_sensor_id;
$$;

SELECT round(lab07_pr.average_value(1), 2) AS avg_sensor_1;
SELECT lab07_pr.average_value(3) AS avg_sensor_3;
```

Фактичний результат з журналу:

```text
CREATE FUNCTION
 avg_sensor_1 
--------------
        24.00
(1 row)

 avg_sensor_3 
--------------
       <NULL>
(1 row)
```

Для датчика 1 середнє становить `24.00`; для датчика 3 повертається `NULL` (відсутність показів, а не нуль).

#### 3. Таблична функція `last_readings` (`RETURNS TABLE`, `DEFAULT` значення):
```sql
CREATE OR REPLACE FUNCTION lab07_pr.last_readings(
    p_sensor_id integer,
    p_limit integer DEFAULT 3
)
RETURNS TABLE (
    reading_id bigint,
    measured_at timestamptz,
    value numeric
)
LANGUAGE sql
STABLE
AS $$
    SELECT r.id, r.measured_at, r.value
    FROM lab07_pr.readings AS r
    WHERE r.sensor_id = p_sensor_id
    ORDER BY r.measured_at DESC, r.id DESC
    LIMIT p_limit;
$$;

SELECT * FROM lab07_pr.last_readings(1)
ORDER BY measured_at DESC, reading_id DESC;

SELECT * FROM lab07_pr.last_readings(1, 2)
ORDER BY measured_at DESC, reading_id DESC;
```

Фактичний результат з журналу:

```text
CREATE FUNCTION
 reading_id |      measured_at       | value 
------------+------------------------+-------
          4 | 2026-10-01 09:30:00+03 | 30.00
          3 | 2026-10-01 09:20:00+03 | 24.00
          2 | 2026-10-01 09:10:00+03 | 22.00
(3 rows)

 reading_id |      measured_at       | value 
------------+------------------------+-------
          4 | 2026-10-01 09:30:00+03 | 30.00
          3 | 2026-10-01 09:20:00+03 | 24.00
(2 rows)
```

#### 4. Самостійна перевірка до Завдання 1:
```sql
SELECT lab07_pr.to_fahrenheit(25) AS fahrenheit_25;
SELECT round(lab07_pr.average_value(2), 2) AS avg_sensor_2;
SELECT * FROM lab07_pr.last_readings(1, 1);
```

Фактичний результат з журналу:

```text
 fahrenheit_25 
---------------
         77.00
(1 row)

 avg_sensor_2 
--------------
        20.00
(1 row)

 reading_id |      measured_at       | value 
------------+------------------------+-------
          4 | 2026-10-01 09:30:00+03 | 30.00
(1 row)
```

Перевірка підтверджує: $25^\circ\text{C} = 77.0^\circ\text{F}$; середнє для датчика 2 = $20.00^\circ\text{C}$; один останній показ датчика 1 = $30.00^\circ\text{C}$.

---

### 3.5. Завдання 2. Програмування мовою PL/pgSQL

#### 1. Розгалуження `IF / ELSIF / ELSE` у функції `temperature_level`:
```sql
CREATE OR REPLACE FUNCTION lab07_pr.temperature_level(
    p_value numeric
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_level text;
BEGIN
    IF p_value IS NULL THEN
        v_level := 'немає даних';
    ELSIF p_value < 25 THEN
        v_level := 'норма';
    ELSIF p_value < 30 THEN
        v_level := 'підвищена';
    ELSE
        v_level := 'висока';
    END IF;

    RETURN v_level;
END;
$$;

SELECT id, value,
       lab07_pr.temperature_level(value) AS level
FROM lab07_pr.readings
WHERE sensor_id = 1
ORDER BY id;
```

Фактичний результат з журналу [savings.txt](file:///home/mafi2/Projects/DataBase-discipline/lab7/savings.txt):

```text
CREATE FUNCTION
 id | value | level  
----+-------+--------
  1 | 20.00 | норма
  2 | 22.00 | норма
  3 | 24.00 | норма
  4 | 30.00 | висока
(4 rows)
```

#### 2. Вибірка в змінну `SELECT INTO` та перевірка `FOUND` у `latest_value`:
```sql
CREATE OR REPLACE FUNCTION lab07_pr.latest_value(
    p_sensor_id integer
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_value lab07_pr.readings.value%TYPE;
BEGIN
    SELECT r.value INTO v_value
    FROM lab07_pr.readings AS r
    WHERE r.sensor_id = p_sensor_id
    ORDER BY r.measured_at DESC, r.id DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    RETURN v_value;
END;
$$;

SELECT lab07_pr.latest_value(1) AS latest_1;
SELECT lab07_pr.latest_value(3) AS latest_3;
```

Фактичний результат:

```text
CREATE FUNCTION
 latest_1 
----------
    30.00
(1 row)

 latest_3 
----------
   <NULL>
(1 row)
```

#### 3. Цикл `FOR` та діагностичні повідомлення `RAISE NOTICE`:
```sql
DO $$
BEGIN
    FOR v_id IN 1..3 LOOP
        RAISE NOTICE 'Датчик %, середнє = %',
            v_id, lab07_pr.average_value(v_id);
    END LOOP;
END;
$$;
```

Фактичний результат з журналу:

```text
NOTICE:  Датчик 1, середнє = 24.0000000000000000
NOTICE:  Датчик 2, середнє = 20.0000000000000000
NOTICE:  Датчик 3, середнє = <NULL>
DO
```

#### 4. Самостійна перевірка до Завдання 2:
```sql
SELECT s.id, s.name,
       lab07_pr.latest_value(s.id) AS latest_temp,
       lab07_pr.temperature_level(lab07_pr.latest_value(s.id)) AS temp_status
FROM lab07_pr.sensors AS s
ORDER BY s.id;
```

Фактичний результат з журналу:

```text
 id |       name       | latest_temp | temp_status 
----+------------------+-------------+-------------
  1 | Лабораторія А    |       30.00 | висока
  2 | Лабораторія Б    |       22.00 | норма
  3 | Резервний датчик |      <NULL> | немає даних
(3 rows)
```

---

### 3.6. Завдання 3. Оброблення очікуваної помилки

```sql
CREATE TABLE lab07_pr.execution_log (
    id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    message text NOT NULL
);

DO $$
BEGIN
    INSERT INTO lab07_pr.execution_log (message)
    VALUES ('До внутрішнього блоку');

    BEGIN
        INSERT INTO lab07_pr.execution_log (message)
        VALUES ('Запис перед помилкою');

        -- Спроба вставити дублікат часової мітки для датчика 1
        INSERT INTO lab07_pr.readings (sensor_id, measured_at, value)
        VALUES (1, '2026-10-01 09:00:00+03', 99);

    EXCEPTION
        WHEN unique_violation THEN
            INSERT INTO lab07_pr.execution_log (message)
            VALUES ('Порушення UNIQUE перехоплено');
    END;

    INSERT INTO lab07_pr.execution_log (message)
    VALUES ('Після внутрішнього блоку');
END;
$$;

SELECT id, message
FROM lab07_pr.execution_log
ORDER BY id;
```

Фактичний результат з журналу [savings.txt](file:///home/mafi2/Projects/DataBase-discipline/lab7/savings.txt):

```text
CREATE TABLE
DO
 id |           message            
----+------------------------------
  1 | До внутрішнього блоку
  3 | Порушення UNIQUE перехоплено
  4 | Після внутрішнього блоку
(3 rows)
```

> [!IMPORTANT]
> **Аналіз поведінки підтранзакції та пропуску ідентифікатора:**  
> Запис `id = 2` («Запис перед помилкою») було додано всередині захищеного блоку, тому під час помилки `unique_violation` PostgreSQL відкотив підтранзакцію до сейвпоінта, анулювавши цей рядок. При цьому лічильник послідовності `IDENTITY` не відкотився, що зумовило стрибок у первинних ключах: `1`, потім одразу `3`, потім `4`.

---

### 3.7. Завдання 4. Створення та виклик процедури

```sql
CREATE OR REPLACE PROCEDURE lab07_pr.set_sensor_active(
    IN p_sensor_id integer,
    IN p_active boolean,
    OUT p_updated integer
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE lab07_pr.sensors AS s
    SET active = p_active
    WHERE s.id = p_sensor_id;

    GET DIAGNOSTICS p_updated = ROW_COUNT;
END;
$$;

BEGIN;

CALL lab07_pr.set_sensor_active(3, false, NULL);

SELECT id, name, active
FROM lab07_pr.sensors WHERE id = 3;

ROLLBACK;

SELECT id, name, active
FROM lab07_pr.sensors WHERE id = 3;

CALL lab07_pr.set_sensor_active(999, false, NULL);
```

Фактичний результат з журналу [savings.txt](file:///home/mafi2/Projects/DataBase-discipline/lab7/savings.txt):

```text
CREATE PROCEDURE
BEGIN
 p_updated 
-----------
         1
(1 row)

 id |       name       | active 
----+------------------+--------
  3 | Резервний датчик | f
(1 row)

ROLLBACK
 id |       name       | active 
----+------------------+--------
  3 | Резервний датчик | t
(1 row)

 p_updated 
-----------
         0
(1 row)
```

Оператор `CALL` успішно повернув параметр `p_updated = 1`. Після `ROLLBACK` статус активності датчика 3 повернувся до початкового `true`. Виклик для неіснуючого датчика 999 повернув `p_updated = 0`.

---

### 3.8. Завдання 5. Тригери BEFORE та AFTER

#### 1. Створення тригерів `readings_prepare` та `readings_audit`:
```sql
CREATE OR REPLACE FUNCTION lab07_pr.prepare_reading()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.note := NULLIF(btrim(NEW.note), '');
    RETURN NEW;
END;
$$;

CREATE TRIGGER readings_prepare
BEFORE INSERT OR UPDATE ON lab07_pr.readings
FOR EACH ROW
EXECUTE FUNCTION lab07_pr.prepare_reading();

CREATE TABLE lab07_pr.reading_audit (
    event_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reading_id bigint NOT NULL,
    operation  text NOT NULL
               CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    old_row    jsonb,
    new_row    jsonb
);

CREATE OR REPLACE FUNCTION lab07_pr.audit_reading()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO lab07_pr.reading_audit
            (reading_id, operation, old_row, new_row)
        VALUES (NEW.id, TG_OP, NULL, to_jsonb(NEW));

    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW IS NOT DISTINCT FROM OLD THEN
            RETURN NULL;
        END IF;

        INSERT INTO lab07_pr.reading_audit
            (reading_id, operation, old_row, new_row)
        VALUES (NEW.id, TG_OP, to_jsonb(OLD), to_jsonb(NEW));

    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO lab07_pr.reading_audit
            (reading_id, operation, old_row, new_row)
        VALUES (OLD.id, TG_OP, to_jsonb(OLD), NULL);
    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER readings_audit
AFTER INSERT OR UPDATE OR DELETE ON lab07_pr.readings
FOR EACH ROW
EXECUTE FUNCTION lab07_pr.audit_reading();
```

#### 2. Перевірка повного DML-циклу та відкату `ROLLBACK`:
```sql
BEGIN;

INSERT INTO lab07_pr.readings (sensor_id, measured_at, value, note)
VALUES (2, '2026-10-01 10:00:00+03', 23, '   Перевірка   ')
RETURNING id, note;

UPDATE lab07_pr.readings
SET value = 24, note = '   Уточнено   '
WHERE sensor_id = 2
  AND measured_at = '2026-10-01 10:00:00+03';

DELETE FROM lab07_pr.readings
WHERE sensor_id = 2
  AND measured_at = '2026-10-01 10:00:00+03';

SELECT event_id, operation,
       old_row ->> 'value' AS old_val,
       new_row ->> 'value' AS new_val,
       new_row ->> 'note'  AS new_note
FROM lab07_pr.reading_audit
ORDER BY event_id;

ROLLBACK;

SELECT count(*) AS audit_rows
FROM lab07_pr.reading_audit;
```

Фактичний результат з журналу [savings.txt](file:///home/mafi2/Projects/DataBase-discipline/lab7/savings.txt):

```text
CREATE FUNCTION
CREATE TRIGGER
CREATE TABLE
CREATE FUNCTION
CREATE TRIGGER
BEGIN
 id |   note    
----+-----------
  8 | Перевірка
(1 row)

INSERT 0 1
UPDATE 1
DELETE 1
 event_id | operation | old_val | new_val | new_note  
----------+-----------+---------+---------+-----------
        1 | INSERT    |         | 23.00   | Перевірка
        2 | UPDATE    | 23.00   | 24.00   | Уточнено
        3 | DELETE    | 24.00   |         | 
(3 rows)

ROLLBACK
 audit_rows 
------------
          0
(1 row)
```

`RETURNING` зафіксував обрізку пробілів: `'Перевірка'`. Аудит зафіксував усі 3 стани. Після `ROLLBACK` лічильник `audit_rows = 0`, що повністю доводить виконання тригерів у загальному транзакційному контексті.

---

### 3.9. Завдання 6. Користувацький агрегат

```sql
CREATE OR REPLACE FUNCTION lab07_pr.weighted_step(
    p_state numeric[],
    p_value numeric,
    p_weight numeric
)
RETURNS numeric[]
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_value IS NULL OR p_weight IS NULL THEN
        RETURN p_state;
    END IF;

    IF p_weight <= 0 THEN
        RAISE EXCEPTION 'Вага має бути додатною'
            USING ERRCODE = '22023';
    END IF;

    RETURN ARRAY[
        p_state[1] + p_value * p_weight,
        p_state[2] + p_weight
    ];
END;
$$;

CREATE OR REPLACE FUNCTION lab07_pr.weighted_final(
    p_state numeric[]
)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT p_state[1] / NULLIF(p_state[2], 0);
$$;

CREATE AGGREGATE lab07_pr.weighted_avg(numeric, numeric) (
    SFUNC = lab07_pr.weighted_step,
    STYPE = numeric[],
    FINALFUNC = lab07_pr.weighted_final,
    INITCOND = '{0,0}'
);

SELECT sensor_id,
       round(avg(value), 2) AS ordinary_avg,
       round(lab07_pr.weighted_avg(value, weight), 2) AS weighted_avg
FROM lab07_pr.readings
GROUP BY sensor_id
ORDER BY sensor_id;

SELECT lab07_pr.weighted_avg(value, weight) AS empty_result
FROM lab07_pr.readings
WHERE sensor_id = 3;

-- Контрольний математичний розрахунок
SELECT sensor_id,
       round(SUM(value * weight) / SUM(weight), 2) AS formula_calc,
       round(lab07_pr.weighted_avg(value, weight), 2) AS aggregate_calc
FROM lab07_pr.readings
GROUP BY sensor_id
ORDER BY sensor_id;
```

Фактичний результат з журналу [savings.txt](file:///home/mafi2/Projects/DataBase-discipline/lab7/savings.txt):

```text
CREATE FUNCTION
CREATE FUNCTION
CREATE AGGREGATE
 sensor_id | ordinary_avg | weighted_avg 
-----------+--------------+--------------
         1 |        24.00 |        24.67
         2 |        20.00 |        20.33
(2 rows)

 empty_result 
--------------
       <NULL>
(1 row)

 sensor_id | formula_calc | aggregate_calc 
-----------+--------------+----------------
         1 |        24.67 |          24.67
         2 |        20.33 |          20.33
(2 rows)
```

Математичне зіставлення: для датчика 1 звичайне середнє дорівнює `24.00`, тоді як середньозважене становить `24.67`, оскільки вищі температури (наприклад, $30.0^\circ\text{C}$ та $22.0^\circ\text{C}$) мали вагу $W = 2$. Розрахунок за формулою `formula_calc` ідеально збігається з результатом агрегату `aggregate_calc`.

---

### 3.10. Завдання 10. Творче індивідуальне завдання «Контроль температури»

#### 1. Додавання датчика «Майстерня» та 4 вимірювань:
```sql
BEGIN;

INSERT INTO lab07_pr.sensors (name)
VALUES ('Майстерня');

INSERT INTO lab07_pr.readings (sensor_id, measured_at, value, weight, note) VALUES
    ((SELECT id FROM lab07_pr.sensors WHERE name = 'Майстерня'), '2026-10-01 11:00:00+03', 23.0, 1.0, '   Старт зміни   '),
    ((SELECT id FROM lab07_pr.sensors WHERE name = 'Майстерня'), '2026-10-01 11:15:00+03', 26.5, 2.0, '   Розігрів   '),
    ((SELECT id FROM lab07_pr.sensors WHERE name = 'Майстерня'), '2026-10-01 11:30:00+03', 28.5, 3.0, '   Перевищення   '),
    ((SELECT id FROM lab07_pr.sensors WHERE name = 'Майстерня'), '2026-10-01 11:45:00+03', 31.0, 1.0, '   Пікове значення   ');

COMMIT;
```

#### 2. Реалізація та перевірка функції `sensor_alarm`:
```sql
CREATE OR REPLACE FUNCTION lab07_pr.sensor_alarm(
    p_sensor_id integer,
    p_threshold numeric DEFAULT 27
)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_latest numeric;
BEGIN
    IF p_threshold IS NULL THEN
        RAISE EXCEPTION 'Поріг спрацювання не може бути NULL'
            USING ERRCODE = '22004',
                  HINT = 'Вкажіть числове значення порогу';
    END IF;

    SELECT r.value INTO v_latest
    FROM lab07_pr.readings AS r
    WHERE r.sensor_id = p_sensor_id
    ORDER BY r.measured_at DESC, r.id DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN 'немає даних';
    ELSIF v_latest > p_threshold THEN
        RETURN 'тривога';
    ELSE
        RETURN 'норма';
    END IF;
END;
$$;

SELECT lab07_pr.sensor_alarm(4) AS alarm_default;
SELECT lab07_pr.sensor_alarm(3) AS alarm_sensor_3;
SELECT lab07_pr.sensor_alarm(4, 35) AS alarm_high_thresh;

-- Валідація помилки на передачу NULL
DO $$
BEGIN
    PERFORM lab07_pr.sensor_alarm(4, NULL);
EXCEPTION
    WHEN null_value_not_allowed THEN
        RAISE NOTICE 'Успішно перехоплено виняток null_value_not_allowed (ERRCODE 22004)';
    WHEN OTHERS THEN
        RAISE NOTICE 'Перехоплено виняток: % (SQLSTATE %)', SQLERRM, SQLSTATE;
END;
$$;
```

Фактичний результат з журналу [savings.txt](file:///home/mafi2/Projects/DataBase-discipline/lab7/savings.txt):

```text
BEGIN
INSERT 0 1
INSERT 0 4
COMMIT
CREATE FUNCTION
 alarm_default 
---------------
 тривога
(1 row)

 alarm_sensor_3 
----------------
 немає даних
(1 row)

 alarm_high_thresh 
-------------------
 норма
(1 row)

NOTICE:  Успішно перехоплено виняток null_value_not_allowed (ERRCODE 22004)
DO
```

#### 3. Модифікація показу, фіксація аудиту та зіставлення середніх:
```sql
UPDATE lab07_pr.readings
SET value = 32.5
WHERE sensor_id = 4 AND measured_at = '2026-10-01 11:45:00+03';

SELECT event_id, operation,
       old_row ->> 'value' AS old_val,
       new_row ->> 'value' AS new_val,
       new_row ->> 'note'  AS new_note
FROM lab07_pr.reading_audit
WHERE reading_id = (
    SELECT id FROM lab07_pr.readings
    WHERE sensor_id = 4 AND measured_at = '2026-10-01 11:45:00+03'
);

SELECT sensor_id,
       round(avg(value), 2) AS ordinary_avg,
       round(lab07_pr.weighted_avg(value, weight), 2) AS weighted_avg
FROM lab07_pr.readings
WHERE sensor_id = 4
GROUP BY sensor_id;
```

Фактичний результат з журналу:

```text
UPDATE 1
 event_id | operation | old_val | new_val |    new_note     
----------+-----------+---------+---------+-----------------
        8 | UPDATE    | 31.00   | 32.50   | Пікове значення
(1 row)

 sensor_id | ordinary_avg | weighted_avg 
-----------+--------------+--------------
         4 |        27.63 |        27.71
(1 row)
```

#### 4. Додаткове завдання (Бонус): Блокування показів для неактивного датчика:
```sql
CREATE OR REPLACE FUNCTION lab07_pr.check_sensor_active()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_active boolean;
BEGIN
    SELECT active INTO v_active
    FROM lab07_pr.sensors
    WHERE id = NEW.sensor_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Датчик з ID=% не існує', NEW.sensor_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    IF NOT v_active THEN
        RAISE EXCEPTION 'Неможливо додати показ: датчик (ID=%) є деактивованим', NEW.sensor_id
            USING ERRCODE = 'check_violation',
                  HINT = 'Активуйте датчик за допомогою процедури set_sensor_active';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER readings_check_active
BEFORE INSERT ON lab07_pr.readings
FOR EACH ROW
EXECUTE FUNCTION lab07_pr.check_sensor_active();

CALL lab07_pr.set_sensor_active(3, false, NULL);

-- Перевірка перехоплення блокування вставки
DO $$
BEGIN
    INSERT INTO lab07_pr.readings (sensor_id, measured_at, value)
    VALUES (3, '2026-10-01 12:00:00+03', 21.0);
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'Успішно перехоплено блокування вставки для деактивованого датчика (check_violation)';
END;
$$;

CALL lab07_pr.set_sensor_active(3, true, NULL);
```

Фактичний результат з журналу:

```text
CREATE FUNCTION
CREATE TRIGGER
 p_updated 
-----------
         1
(1 row)

NOTICE:  Успішно перехоплено блокування вставки для деактивованого датчика (check_violation)
DO
 p_updated 
-----------
         1
(1 row)
```

> [!TIP]
> **Чому `RAISE EXCEPTION`, а не `RETURN NULL`:**  
> Якщо у валідаційному `BEFORE`-тригері повернути `RETURN NULL`, команда вставки тихо ігнорується без виведення помилки. Клієнтська програма отримує успішний статус (`INSERT 0 0`), що створює ризик непомітної втрати критичних даних. Використання `RAISE EXCEPTION` гарантує ясне сповіщення клієнта про порушення бізнес-правила системи.

---

## 4. Відповіді на контрольні питання

### 1. Чим відрізняється SQL-функція від функції PL/pgSQL? Коли доцільніше використовувати кожну?
SQL-функція складається з декларативних SQL-операторів і не підтримує оголошення локальних змінних, циклів та обробки винятків. Оптимізатор запитів PostgreSQL може «вбудовувати» (inlining) прості SQL-функції безпосередньо в план виконання загального запиту, усуваючи накладні витрати на виклик.  
Функція мовою PL/pgSQL є повноцінною процедурною програмою зі своєю системою змінних, умовними конструкціями (`IF / ELSIF / ELSE`), циклами та перехопленням винятків (`EXCEPTION`). Вона виконується окремим інтерпретатором PL/pgSQL.  
**Критерій вибору:** прості математичні формули, обчислення колонок або базові `SELECT`-обгортки доцільно писати мовою SQL для максимальної швидкодії; складні бізнес-правила з розгалуженнями, валідаціями, генерацією помилок та динамічними курсорами реалізуються мовою PL/pgSQL.

### 2. Чому для функції читання вимірювань обрано STABLE, а для переведення температури — IMMUTABLE?
Формула конвертації градусів Цельсія у Фаренгейт ($F = C \cdot 9/5 + 32$) є строго детермінованою: однаковий аргумент завжди повертає ідентичний результат незалежно від стану бази даних, що відповідає категорії `IMMUTABLE`. Це дозволяє СКБД кешувати значення на етапі компіляції запиту та будувати індекси по виразах.  
Функція `average_value` зчитує покази з таблиці `readings`. Вміст таблиці є стабільним у межах одного оператора або сканування, але змінюється між різними транзакціями, що строго відповідає категорії `STABLE`.

### 3. Що означають DECLARE, SELECT ... INTO, FOUND і RETURN у PL/pgSQL?
- `DECLARE`: ключове слово, що відкриває секцію оголошення локальних змінних, констант і курсорів блоку.
- `SELECT ... INTO`: конструкція запису значень результуючого рядка запиту в скалярні змінні або запис `RECORD`.
- `FOUND`: автоматична системна булева змінна, яка приймає значення `true`, якщо попередня SQL-команда (`SELECT INTO`, `INSERT`, `UPDATE`, `DELETE`) обробила хоча б один рядок.
- `RETURN`: оператор завершення виконання функції та повернення результату викликаючому запиту.

### 4. Чим відрізняються функція та процедура за способом виклику? Що повертає параметр OUT?
Функція викликається всередині SQL-виразів (`SELECT func()`, `WHERE func() = 1`), має обов'язковий декларований тип повернення (`RETURNS`) і не може містити явного керування транзакціями.  
Процедура викликається окремим оператором `CALL proc(...)`, не має розділу `RETURNS`, а всі значення повертає через параметри з модифікатором `OUT` (або `INOUT`). На відміну від функції, процедура здатна керувати транзакціями (виконувати `COMMIT` і `ROLLBACK`), якщо викликана поза активною транзакцією клієнта.

### 5. Чому після перехопленого unique_violation не зберігся запис, вставлений перед помилкою всередині внутрішнього блоку?
Секція `EXCEPTION` у вкладеному блоці `BEGIN ... END` неявно створює точку збереження транзакції (savepoint). У разі виникнення помилки ядро PostgreSQL виконує автоматичний відкат усіх дій цієї локальної підтранзакції до сейвпоінта перед передачею керування у гілку `WHEN`. Відповідно, попередній рядок, записаний усередині цього блоку до точки збою, безповоротно скасовується.

### 6. Яку інформацію містять OLD, NEW і TG_OP? Чим відрізняється BEFORE від AFTER?
- `TG_OP`: містить текстовий ідентифікатор ініціюючої події (`'INSERT'`, `'UPDATE'`, `'DELETE'`).
- `NEW`: містить новий образ рядка (доступний в операціях `INSERT` та `UPDATE`).
- `OLD`: містить попередній образ рядка до його модифікації чи видалення (доступний в `UPDATE` та `DELETE`).  
**Відмінність:** Тригер `BEFORE` спрацьовує до збереження даних на диск, дозволяє валідувати або нормалізувати поля `NEW` і вимагає `RETURN NEW`. Тригер `AFTER` спрацьовує після фіксації рядка в таблиці, використовується для асинхронного аудиту й каскадів, а його повернене значення ігнорується СКБД.

### 7. Чому журнал, заповнений AFTER-тригером, очищується після ROLLBACK?
Рядкові тригери PostgreSQL виконуються всередині того самого контексту транзакції, що й команда, яка їх викликала. Записи в таблицю аудиту `reading_audit`, створені функцією `audit_reading`, стають повноцінною частиною поточної транзакції. У разі виклику `ROLLBACK` скасовуються всі зміни транзакції без винятку, включно із записами аудиту.

### 8. Для чого потрібні SFUNC, STYPE, FINALFUNC і INITCOND в агрегаті?
- `STYPE`: визначає тип даних акумулятора внутрішнього стану (наприклад, масив `numeric[]`).
- `INITCOND`: задає початкове значення акумулятора до початку обробки рядків (`'{0,0}'`).
- `SFUNC` (State Transition Function): функція, що викликається для кожного вхідного кортежу та оновлює акумулятор стану.
- `FINALFUNC` (Final Calculation Function): функція, що бере фінальний стан після обробки всіх рядків групи та обчислює кінцевий скалярний результат.

---

## 5. Загальні висновки

Під час виконання лабораторної роботи № 7 було досягнуто таких технічних результатів:

1. **Опанування серверного програмування:** Засвоєно методи розробки бізнес-логіки безпосередньо в реляційному ядрі PostgreSQL за допомогою функцій, процедур, тригерів та користувацьких агрегатів.
2. **Розмежування типів функцій:** Досліджено різницю між декларативними SQL-функціями (можливість інлайнінгу) та імперативними PL/pgSQL-функціями з динамічною типізацією (`%TYPE`, `%ROWTYPE`), умовними розгалуженнями та перевіркою `FOUND`.
3. **Оптимізація та детермінованість:** Проаналізовано рівні мінливості (`IMMUTABLE`, `STABLE`, `VOLATILE`) та підтверджено ефективність модифікатора `STRICT` для автоматичного відсікання значень `NULL`.
4. **Транзакційне керування процедур:** Реалізовано процедуру `set_sensor_active` з параметром `OUT`, діагностикою модифікованих рядків (`ROW_COUNT`) та верифіковано її виклик через оператор `CALL`.
5. **Механіка локальних підтранзакцій:** Доведено експериментально дію сейвпоінтів у блоках `EXCEPTION WHEN`: локальні зміни до моменту збою відкочуються, лічильники `IDENTITY` продовжують монотонне зростання з фіксацією пропуску, а зовнішня транзакція зберігає працездатність.
6. **Тригерні автомати аудиту та нормалізації:** Спроєктовано `BEFORE`-тригер `readings_prepare` для очищення крайніх пробілів та заміни порожніх рядків на `NULL`, а також `AFTER`-тригер `readings_audit` зі збереженням знімків рядків у форматі `jsonb`. Доведено залежність тригерного аудиту від загальної транзакції при `ROLLBACK`.
7. **Користувацька агрегація даних:** Реалізовано кінцевий автомат агрегату `weighted_avg` на базі акумулятора `numeric[]`. Математично обґрунтовано розбіжність між арифметичним середнім ($24.00^\circ\text{C}$) та середньозваженим показником ($24.67^\circ\text{C}$) для датчика з нерівномірними вагами показів.
8. **Творча інженерна реалізація:** Розширено схему датчиком «Майстерня», реалізовано сигналізацію `sensor_alarm` з валідацією `NULL`-порогу (`RAISE EXCEPTION`), розроблено захисний тригер перевірки активності датчика та доведено неприпустимість використання `RETURN NULL` замість генерації винятку в критичних валідаціях.
9. **Дисципліна ізоляції:** Усі компоненти реалізовано у виділеній схемі `lab07_pr` із суворою прямою кваліфікацією без мутації системного параметра `search_path`.
