-- 04_owner_verification.sql
-- Перевірка підсумкового стану таблиці від імені власника (postgres) та команди очищення

RESET ROLE;

-- 1. Фінальна перевірка збережених значень у таблиці
SELECT current_user, id, name, rating FROM lab_columns.students;

-- 2. Очищення навчальних об'єктів після завершення лабораторної (опціонально)
/*
RESET ROLE;
DROP TABLE IF EXISTS lab_columns.students;
DROP SCHEMA IF EXISTS lab_columns CASCADE;
REVOKE column_user FROM postgres;
DROP ROLE IF EXISTS column_user;
*/
