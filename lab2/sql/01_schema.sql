-- 01_schema.sql
-- Створення схеми lab_columns, таблиці students та початкове наповнення даними від імені власника (postgres)

RESET ROLE;

-- Створення схеми-контейнера для ізоляції об'єктів лабораторної роботи
CREATE SCHEMA IF NOT EXISTS lab_columns;

-- Створення таблиці students
CREATE TABLE IF NOT EXISTS lab_columns.students (
    id INTEGER PRIMARY KEY,
    name TEXT,
    rating INTEGER
);

-- Додавання початкового запису
INSERT INTO lab_columns.students (id, name, rating)
VALUES (1, 'Illia', 87);

-- Перевірка результату вставки
SELECT * FROM lab_columns.students;
