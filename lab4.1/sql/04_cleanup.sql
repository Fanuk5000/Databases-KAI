-- ============================================================================
-- Лабораторна робота 4.1: Часові типи та типи діапазонів у PostgreSQL
-- Частина 4: Очищення навчальних ресурсів (Teardown)
-- ============================================================================

DROP TABLE IF EXISTS lab41.exam_grades CASCADE;
DROP TABLE IF EXISTS lab41.room_bookings CASCADE;
DROP TABLE IF EXISTS lab41.work_shifts CASCADE;

-- Опціонально: видалення навчальної схеми
-- DROP SCHEMA IF EXISTS lab41 CASCADE;

-- Розширення btree_gist зазвичай залишається активним в екземплярі:
-- DROP EXTENSION IF EXISTS btree_gist;
