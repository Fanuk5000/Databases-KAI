-- ============================================================================
-- Частина 3: Індексація зовнішніх ключів, представлення (VIEW) та JOIN-запити
-- ============================================================================

-- 1. Створення вторинних індексів на зовнішніх ключах
CREATE INDEX idx_students_group_id ON lab_students(group_id);
CREATE INDEX idx_enrollments_subject_id ON lab_enrollments(subject_id);
CREATE INDEX idx_subjects_prerequisite_id ON lab_subjects(prerequisite_id);

-- 2. Створення представлення для зведеної інформації про студентів та дисципліни
CREATE OR REPLACE VIEW v_student_subjects AS
SELECT
    s.id AS student_id,
    s.name AS student_name,
    g.group_name,
    sub.subject_name,
    e.grade,
    e.status
FROM lab_enrollments AS e
JOIN lab_students AS s ON e.student_id = s.id
JOIN lab_groups AS g ON s.group_id = g.id
JOIN lab_subjects AS sub ON e.subject_id = sub.id;

-- Вибірка з представлення
SELECT *
FROM v_student_subjects
ORDER BY student_name, subject_name;

-- 3. Багатотабличні JOIN-запити для аудиту зв'язків

-- 3.1. Студенти з групою та куратором (LEFT JOIN для безпеки при NULL curator_id)
SELECT
    s.name AS student,
    g.group_name,
    COALESCE(t.full_name, '— немає куратора —') AS curator
FROM lab_students AS s
JOIN lab_groups AS g ON s.group_id = g.id
LEFT JOIN lab_teachers AS t ON g.curator_id = t.id
ORDER BY s.name;

-- 3.2. Викладачі та дисципліни, які вони викладають
SELECT
    t.full_name AS teacher,
    sub.subject_name,
    sub.credits
FROM lab_teacher_subjects AS ts
JOIN lab_teachers AS t ON ts.teacher_id = t.id
JOIN lab_subjects AS sub ON ts.subject_id = sub.id
ORDER BY t.full_name, sub.subject_name;
