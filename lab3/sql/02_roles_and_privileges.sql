-- ============================================================================
-- Лабораторна робота: Конфігурація, ролі, схеми й керування доступом у PostgreSQL
-- Скрипт 02: Створення навчальних ролей та налаштування матриці привілеїв
-- Середовище: Supabase (PostgreSQL)
-- Роль виконання: postgres (owner)
-- ============================================================================

RESET ROLE;

-- 1. Створення ролей без права самостійного входу (NOLOGIN)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'lab_reader') THEN
        CREATE ROLE lab_reader NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'lab_editor') THEN
        CREATE ROLE lab_editor NOLOGIN;
    END IF;
END $$;

-- 2. Надання адміністративній ролі postgres дозволу перемикатися на створені ролі
-- Для PostgreSQL 16+ використовується конструкція WITH SET TRUE
GRANT lab_reader, lab_editor TO postgres WITH SET TRUE;

-- 3. Надання привілею USAGE на схему lab_demo (необхідно для доступу до об'єктів схеми)
GRANT USAGE
ON SCHEMA lab_demo
TO lab_reader, lab_editor;

-- 4. Надання ролі lab_reader привілею лише на читання
GRANT SELECT
ON lab_demo.students
TO lab_reader;

-- 5. Надання ролі lab_editor повного набору прав маніпуляції даними (DML)
GRANT SELECT, INSERT, UPDATE, DELETE
ON lab_demo.students
TO lab_editor;
