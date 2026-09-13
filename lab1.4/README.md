# PostgreSQL Lab 1.4: Column-Level Privileges & Roles in Supabase

Лабораторна робота з дисципліни «Бази даних». Проєкт присвячено дослідженню рольової моделі керування доступом (Role-Based Access Control, RBAC) у СУБД PostgreSQL на інфраструктурі Supabase, розмежуванню прав на рівні окремих стовпців таблиці (Column-Level Privileges), роботі з ролями без права прямого входу (`NOLOGIN`), тимчасовому перемиканню контексту користувача через `SET ROLE` / `RESET ROLE` та обробці винятків безпеки ядра СУБД (`ERROR: 42501`).

---

## Структура проєкту

```text
lab1.4/
├── README.md                   # Огляд проєкту, структура та протокол виконання
├── todo.md                     # Детальний чекліст, інструкції та теоретична база
├── savings.txt                 # Сирі збережені логи виконання запитів у Supabase
├── sql/
│   ├── 01_schema.sql           # Створення схеми lab_columns, таблиці students та вставка початкових даних
│   ├── 02_roles_and_privileges.sql # Створення ролі column_user та видача гранулярних привілеїв
│   ├── 03_test_column_user.sql # Перевірка читання, успішне оновлення name та заблоковане оновлення rating
│   └── 04_owner_verification.sql # Фінальна верифікація даних від імені postgres та команди teardown
└── docs/
    └── report.md               # Повний академічний лабораторний звіт
```

---

## Швидкий старт

### Виконання у Supabase SQL Editor

1. Відкрийте проєкт у **Supabase** ➔ розділ **SQL Editor**.
2. Послідовно виконайте SQL-скрипти з папки `sql/`:
   - `sql/01_schema.sql` — ініціалізація схеми та таблиці від імені `postgres`. *(При появі діалогу про RLS обрати «Run Without RLS»)*.
   - `sql/02_roles_and_privileges.sql` — створення ролі `column_user` та надання доступу до схеми, читання таблиці й модифікації стовпця `name`.
   - `sql/03_test_column_user.sql` — тестування операцій під роллю `column_user`.
   - `sql/04_owner_verification.sql` — контрольна перевірка таблиці під роллю `postgres`.

---

## Протокол виконання та логи сесії (Execution Logs)

Нижче наведено фактичні логи виконання операцій згідно з `savings.txt`.

### 1. Початковий стан таблиці (власник `postgres`)

```text
| id | name  | rating |
| -- | ----- | ------ |
| 1  | Illia | 87     |
```

### 2. Перевірка читання від імені `column_user`

Команда перемикання контексту та читання:
```sql
SET ROLE column_user;
SELECT current_user, name, rating FROM lab_columns.students;
```

Результат:
```text
| current_user | name  | rating |
| ------------ | ----- | ------ |
| column_user  | Illia | 87     |
```

### 3. Дозволена модифікація стовпця `name`

Команда оновлення дозволеного стовпця:
```sql
SET ROLE column_user;
UPDATE lab_columns.students
SET name = 'Denis'
WHERE id = 1
RETURNING *;
```

Результат:
```text
| id | name  | rating |
| -- | ----- | ------ |
| 1  | Denis | 87     |
```

### 4. Заборонена модифікація стовпця `rating`

Спроба модифікації закритого стовпця під роллю `column_user`:
```sql
SET ROLE column_user;
UPDATE lab_columns.students
SET rating = 87
WHERE id = 1;
```

Результат виконання:
```text
Error: Failed to run sql query: ERROR: 42501: permission denied for table students
```

*Код помилки `42501` свідчить про штатне спрацьовування захисту PostgreSQL (insufficient privilege).*

### 5. Підсумковий стан таблиці від імені власника `postgres`

Повернення до базової ролі сесії:
```sql
RESET ROLE;
SELECT current_user, id, name, rating FROM lab_columns.students;
```

Результат:
```text
| current_user | id | name  | rating |
| ------------ | -- | ----- | ------ |
| postgres     | 1  | Denis | 87     |
```

---

## Підсумкова динаміка зміни даних

| Параметр | Початковий стан (`postgres`) | Після дозволеної зміни (`column_user`) | Після забороненої спроби (`column_user`) | Фінальний стан (`postgres`) |
| :--- | :--- | :--- | :--- | :--- |
| **`current_user`** | `postgres` | `column_user` | `column_user` | `postgres` |
| **`id`** | `1` | `1` | `1` | `1` |
| **`name`** | `Illia` | `Denis` (успішно оновлено) | `Denis` | `Denis` |
| **`rating`** | `87` | `87` | `87` (блокування доступу) | `87` |
