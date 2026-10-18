-- ============================================================================
-- Частина 1: Типи даних ENUM, базові сутності (1:1 та 1:N), валідація та тести
-- ============================================================================

-- 1. Створення користувацьких перелічуваних типів (ENUM)
CREATE TYPE student_status AS ENUM ('active', 'academic_leave', 'expelled');
CREATE TYPE enrollment_status AS ENUM ('enrolled', 'completed', 'failed');

-- 2. Таблиця викладачів (lab_teachers)
CREATE TABLE lab_teachers (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name varchar(100) NOT NULL,
    email varchar(100) NOT NULL UNIQUE
);

-- Наповнення викладачів
INSERT INTO lab_teachers (full_name, email)
VALUES
    ('Коваленко О. І.', 'kovalenko@example.edu'),
    ('Сидоренко М. П.', 'sydorenko@example.edu');

SELECT * FROM lab_teachers ORDER BY id;

-- 3. Таблиця груп зі зв'язком 1:1 до куратора (lab_groups)
CREATE TABLE lab_groups (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    group_name varchar(50) NOT NULL UNIQUE,
    curator_id integer UNIQUE
        REFERENCES lab_teachers(id)
        ON DELETE SET NULL
);

-- Наповнення груп
INSERT INTO lab_groups (group_name, curator_id)
VALUES
    ('Б-121-24-1-ПІ', 1),
    ('Б-121-24-2-ПІ', 2);

SELECT * FROM lab_groups ORDER BY id;

-- 4. Таблиця студентів зі зв'язком 1:N, CHECK та м'яким видаленням (lab_students)
CREATE TABLE lab_students (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name varchar(100) NOT NULL,
    rating integer CHECK (rating >= 0 AND rating <= 100),
    status student_status NOT NULL DEFAULT 'active',
    group_id integer NOT NULL
        REFERENCES lab_groups(id)
        ON DELETE RESTRICT,
    is_deleted boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Наповнення студентів
INSERT INTO lab_students (name, rating, group_id)
VALUES
    ('Анна', 90, 1),
    ('Петро', 75, 1),
    ('Олена', 85, 2),
    ('Дмитро', 60, 2);

SELECT id, name, rating, status, group_id, is_deleted, created_at
FROM lab_students
ORDER BY id;

-- 5. Негативні тести цілісності у транзакції (BEGIN / ROLLBACK)

-- 5.1. Порушення зовнішнього ключа: неіснуюча група 999
BEGIN;
INSERT INTO lab_students (name, rating, group_id)
VALUES ('Тест', 80, 999);
ROLLBACK;

-- 5.2. Порушення обмеження CHECK: рейтинг поза межами [0..100]
BEGIN;
INSERT INTO lab_students (name, rating, group_id)
VALUES ('Тест', 150, 1);
ROLLBACK;
