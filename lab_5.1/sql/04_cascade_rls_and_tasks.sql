-- ============================================================================
-- Частина 4: Каскадні операції, RLS, самостійні завдання та тести цілісності
-- ============================================================================

-- 1. Перевірка каскадних операцій (ON DELETE)

-- 1.1. Перевірка ON DELETE CASCADE (видалення студента видаляє його оцінки)
DELETE FROM lab_students WHERE name = 'Дмитро';

-- Перевірка відсутності записів у lab_enrollments для student_id = 4
SELECT * FROM lab_enrollments WHERE student_id = 4;

-- 1.2. Перевірка ON DELETE RESTRICT (заборона видалення групи з наявними студентами)
BEGIN;
DELETE FROM lab_groups WHERE group_name = 'Б-121-24-1-ПІ';
ROLLBACK;

-- 2. Налаштування Row Level Security (RLS) у Supabase
ALTER TABLE lab_students ENABLE ROW LEVEL SECURITY;

CREATE POLICY students_select_authenticated
ON lab_students
FOR SELECT
TO authenticated
USING (true);

-- 3. Самостійні завдання

-- 3.1. Додавання нового викладача та нової групи (збереження зв'язку 1:1)
INSERT INTO lab_teachers (full_name, email)
VALUES ('Григоренко В. С.', 'hryhorenko@example.edu');

INSERT INTO lab_groups (group_name, curator_id)
VALUES ('Б-121-24-3-ПІ', (SELECT id FROM lab_teachers WHERE email = 'hryhorenko@example.edu'));

SELECT g.group_name, t.full_name AS curator
FROM lab_groups g
JOIN lab_teachers t ON g.curator_id = t.id
WHERE g.group_name = 'Б-121-24-3-ПІ';

-- 3.2. Додавання дисципліни «Машинне навчання» з передумовою «Програмування»
INSERT INTO lab_subjects (subject_name, credits, prerequisite_id)
VALUES (
    'Машинне навчання',
    5,
    (SELECT id FROM lab_subjects WHERE subject_name = 'Програмування')
);

SELECT s.subject_name, s.credits, pre.subject_name AS prerequisite
FROM lab_subjects s
LEFT JOIN lab_subjects pre ON s.prerequisite_id = pre.id
WHERE s.subject_name = 'Машинне навчання';

-- 3.3. Створення представлення навантаження викладачів (v_teacher_load)
CREATE OR REPLACE VIEW v_teacher_load AS
SELECT
    t.id AS teacher_id,
    t.full_name,
    COUNT(ts.subject_id) AS total_subjects
FROM lab_teachers t
LEFT JOIN lab_teacher_subjects ts ON t.id = ts.teacher_id
GROUP BY t.id, t.full_name;

SELECT * FROM v_teacher_load ORDER BY total_subjects DESC, full_name;

-- 3.4. Спроба видалити дисципліну з активними зарахуваннями (ON DELETE RESTRICT)
BEGIN;
DELETE FROM lab_subjects WHERE subject_name = 'Бази даних';
ROLLBACK;

-- 4. Завдання для контрольної перевірки цілісності (Verification Tests)

-- 4.1. Порушення UNIQUE для куратора (спроба прив'язати зайнятого куратора)
BEGIN;
INSERT INTO lab_groups (group_name, curator_id)
VALUES ('Б-121-24-4-ПІ', 1);
ROLLBACK;

-- 4.2. Повторне зарахування (порушення складеного первинного ключа PRIMARY KEY)
BEGIN;
INSERT INTO lab_enrollments (student_id, subject_id)
VALUES (1, 1);
ROLLBACK;

-- 4.3. Некоректний статус студента (порушення типу student_status ENUM)
BEGIN;
UPDATE lab_students SET status = 'graduated' WHERE id = 1;
ROLLBACK;
