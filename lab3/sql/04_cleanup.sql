-- ============================================================================
-- Лабораторна робота: Конфігурація, ролі, схеми й керування доступом у PostgreSQL
-- Скрипт 04: Очищення навчальних об'єктів (Teardown)
-- Середовище: Supabase (PostgreSQL)
-- Роль виконання: postgres (owner)
-- ============================================================================

RESET ROLE;

-- 1. Відкликання налаштованих правил привілеїв за замовчуванням
ALTER DEFAULT PRIVILEGES
FOR ROLE postgres
IN SCHEMA lab_demo
REVOKE SELECT ON TABLES FROM lab_reader;

-- 2. Видалення навчальної схеми разом із її таблицями
DROP SCHEMA IF EXISTS lab_demo CASCADE;

-- 3. Відкликання прав та видалення навчальних ролей
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA lab_demo FROM lab_reader, lab_editor;
REVOKE ALL PRIVILEGES ON SCHEMA lab_demo FROM lab_reader, lab_editor;

REVOKE lab_reader, lab_editor FROM postgres;
REVOKE lab_member FROM postgres;

DROP ROLE IF EXISTS lab_member;
DROP ROLE IF EXISTS lab_editor;
DROP ROLE IF EXISTS lab_reader;
