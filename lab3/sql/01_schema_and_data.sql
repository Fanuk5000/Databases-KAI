-- ============================================================================
-- Лабораторна робота: Конфігурація, ролі, схеми й керування доступом у PostgreSQL
-- Скрипт 01: Ініціалізація простору імен (схеми), таблиці та навчальних даних
-- Середовище: Supabase (PostgreSQL)
-- Роль виконання: postgres (owner)
-- ============================================================================

RESET ROLE;

-- 1. Створення ізольованої схеми lab_demo
CREATE SCHEMA IF NOT EXISTS lab_demo;

-- 2. Створення навчальної таблиці students
CREATE TABLE IF NOT EXISTS lab_demo.students (
    id         INTEGER PRIMARY KEY,
    name       TEXT NOT NULL,
    group_name TEXT NOT NULL,
    rating     INTEGER
);

-- 3. Додавання початкового набору даних
INSERT INTO lab_demo.students (id, name, group_name, rating)
VALUES
    (1, 'Illia',   'B-121', 100),
    (2, 'Maksym',  'B-123', 100),
    (3, 'Natasha', 'B-121', 95)
ON CONFLICT (id) DO UPDATE 
SET name = EXCLUDED.name,
    group_name = EXCLUDED.group_name,
    rating = EXCLUDED.rating;

-- 4. Перевірка доданих записів
SELECT *
FROM lab_demo.students
ORDER BY id;
