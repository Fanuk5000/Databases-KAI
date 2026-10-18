-- ============================================================================
-- Частина 5: Очищення навчальних ресурсів (Teardown)
-- ============================================================================

-- Видалення представлень
DROP VIEW IF EXISTS v_teacher_load;
DROP VIEW IF EXISTS v_student_subjects;

-- Видалення таблиць у порядку зворотному до залежностей
DROP TABLE IF EXISTS lab_enrollments;
DROP TABLE IF EXISTS lab_teacher_subjects;
DROP TABLE IF EXISTS lab_subjects;
DROP TABLE IF EXISTS lab_students;
DROP TABLE IF EXISTS lab_groups;
DROP TABLE IF EXISTS lab_teachers;

-- Видалення користувацьких типів ENUM
DROP TYPE IF EXISTS student_status;
DROP TYPE IF EXISTS enrollment_status;
