-- ============================================================================
-- Лабораторна робота: Конфігурація, ролі, схеми й керування доступом у PostgreSQL
-- Скрипт 03: Сценарії верифікації прав доступу, сеансових змінних та каталогів
-- Середовище: Supabase (PostgreSQL)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Сценарій 1: Інспекція підключення та системних каталогів
-- ----------------------------------------------------------------------------
RESET ROLE;

SELECT 
    current_database(),
    current_user,
    session_user;

SELECT schemaname, tablename, tableowner
FROM pg_tables
WHERE schemaname = 'lab_demo';

-- ----------------------------------------------------------------------------
-- Сценарій 2: Верифікація ролі читача (lab_reader)
-- ----------------------------------------------------------------------------
-- Дозволена операція читання
SET ROLE lab_reader;

SELECT
    current_user,
    id,
    name,
    group_name,
    rating
FROM lab_demo.students
ORDER BY id;

RESET ROLE;

-- Заборонена операція модифікації (очікується помилка permission denied)
SET ROLE lab_reader;

UPDATE lab_demo.students
SET rating = 60 
WHERE id = 1;

RESET ROLE;

-- ----------------------------------------------------------------------------
-- Сценарій 3: Верифікація ролі редактора (lab_editor)
-- ----------------------------------------------------------------------------
-- Додавання запису (INSERT RETURNING *)
SET ROLE lab_editor;

INSERT INTO lab_demo.students (id, name, group_name, rating)
VALUES (4, 'Дмитро', 'B-121', 80)
RETURNING *;

RESET ROLE;

-- Зміна запису (UPDATE RETURNING *)
SET ROLE lab_editor;

UPDATE lab_demo.students
SET rating = 90
WHERE id = 4
RETURNING *;

RESET ROLE;

-- Видалення запису (DELETE RETURNING *)
SET ROLE lab_editor;

DELETE FROM lab_demo.students
WHERE id = 4
RETURNING *;

RESET ROLE;

-- ----------------------------------------------------------------------------
-- Сценарій 4: Точкове відкликання привілею UPDATE (REVOKE)
-- ----------------------------------------------------------------------------
RESET ROLE;

REVOKE UPDATE
ON lab_demo.students
FROM lab_editor;

-- Спроба оновлення після відкликання (очікується помилка permission denied)
SET ROLE lab_editor;

UPDATE lab_demo.students
SET rating = 1  
WHERE id = 1;

RESET ROLE;

-- Перевірка збереження права читання
SET ROLE lab_editor;

SELECT *
FROM lab_demo.students
ORDER BY id;

RESET ROLE;

-- ----------------------------------------------------------------------------
-- Сценарій 5: Дослідження групової ролі та успадкування (INHERIT)
-- ----------------------------------------------------------------------------
RESET ROLE;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'lab_member') THEN
        CREATE ROLE lab_member NOLOGIN INHERIT;
    END IF;
END $$;

GRANT lab_reader TO lab_member;
GRANT lab_member TO postgres WITH SET TRUE;

-- Читання через успадковане членство у групі
SET ROLE lab_member;

SELECT
    current_user,
    id,
    name,
    group_name
FROM lab_demo.students
ORDER BY id;

RESET ROLE;

-- Відкликання членства в групі
REVOKE lab_reader FROM lab_member;

-- Перевірка блокування доступу після виключення з групи (очікується помилка)
SET ROLE lab_member;

SELECT *
FROM lab_demo.students;

RESET ROLE;

-- ----------------------------------------------------------------------------
-- Сценарій 6: Інспекція атрибутів ролей у pg_roles
-- ----------------------------------------------------------------------------
SELECT 
    rolname, 
    rolcanlogin, 
    rolsuper, 
    rolcreatedb, 
    rolcreaterole, 
    rolinherit 
FROM pg_roles
WHERE rolname IN ('postgres', 'lab_reader', 'lab_editor', 'lab_member')
ORDER BY rolname;

-- ----------------------------------------------------------------------------
-- Сценарій 7: Керування шляхом пошуку об'єктів (search_path)
-- ----------------------------------------------------------------------------
SHOW search_path;

-- Встановлення власної схеми на початок пошуку
SET search_path TO lab_demo;

-- Звернення через некваліфіковане (коротке) ім'я
SELECT *
FROM students
ORDER BY id;

-- Повернення системного значення та звернення за кваліфікованим іменем
RESET search_path;

SELECT *
FROM lab_demo.students
ORDER BY id;

-- ----------------------------------------------------------------------------
-- Сценарій 8: Керування параметром сеансу statement_timeout
-- ----------------------------------------------------------------------------
SHOW statement_timeout;

SET statement_timeout = '5s';
SHOW statement_timeout;

RESET statement_timeout;
SHOW statement_timeout;

-- ----------------------------------------------------------------------------
-- Сценарій 9: Аналіз контекстів параметрів у pg_settings
-- ----------------------------------------------------------------------------
SELECT 
    name, 
    setting, 
    unit, 
    context, 
    pending_restart 
FROM pg_settings
WHERE name IN ('statement_timeout', 'max_connections');

-- ----------------------------------------------------------------------------
-- Сценарій 10: Автоматичні привілеї майбутніх об'єктів (ALTER DEFAULT PRIVILEGES)
-- ----------------------------------------------------------------------------
RESET ROLE;

ALTER DEFAULT PRIVILEGES
FOR ROLE postgres
IN SCHEMA lab_demo
GRANT SELECT ON TABLES TO lab_reader;

-- Створення нової таблиці від імені postgres
CREATE TABLE IF NOT EXISTS lab_demo.notes (
    message TEXT
);

INSERT INTO lab_demo.notes
VALUES ('Навчальна нотатка');

-- Перевірка читання роллю lab_reader без явного виклику GRANT на таблицю notes
SET ROLE lab_reader;

SELECT *
FROM lab_demo.notes;

RESET ROLE;
