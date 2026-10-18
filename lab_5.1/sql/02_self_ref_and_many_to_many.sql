-- ============================================================================
-- Частина 2: Дисципліни з самопосиланням та зв'язки Багато-до-Багатьох (N:M)
-- ============================================================================

-- 1. Таблиця дисциплін із самопосиланням (lab_subjects)
CREATE TABLE lab_subjects (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    subject_name varchar(100) NOT NULL UNIQUE,
    credits integer NOT NULL CHECK (credits > 0),
    prerequisite_id integer REFERENCES lab_subjects(id)
        ON DELETE SET NULL
);

-- Наповнення дисциплін (ієрархія передумов через підзапити)
INSERT INTO lab_subjects (subject_name, credits, prerequisite_id)
VALUES
    ('Програмування', 5, NULL),
    ('Бази даних', 4, NULL);

INSERT INTO lab_subjects (subject_name, credits, prerequisite_id)
VALUES
    ('Комп''ютерні мережі', 4, (SELECT id FROM lab_subjects WHERE subject_name = 'Програмування')),
    ('Веб-розробка', 5, (SELECT id FROM lab_subjects WHERE subject_name = 'Бази даних'));

INSERT INTO lab_subjects (subject_name, credits, prerequisite_id)
VALUES
    ('Розподілені системи', 6, (SELECT id FROM lab_subjects WHERE subject_name = 'Комп''ютерні мережі'));

SELECT id, subject_name, credits, prerequisite_id FROM lab_subjects ORDER BY id;

-- 2. Сполучна таблиця N:M «Викладачі — Дисципліни» (lab_teacher_subjects)
CREATE TABLE lab_teacher_subjects (
    teacher_id integer NOT NULL
        REFERENCES lab_teachers(id)
        ON DELETE CASCADE,
    subject_id integer NOT NULL
        REFERENCES lab_subjects(id)
        ON DELETE CASCADE,
    PRIMARY KEY (teacher_id, subject_id)
);

-- Наповнення закріплення викладачів за дисциплінами
INSERT INTO lab_teacher_subjects (teacher_id, subject_id)
VALUES
    (1, 1), -- Коваленко викладає Програмування
    (1, 4), -- Коваленко викладає Веб-розробку
    (2, 2), -- Сидоренко викладає Бази даних
    (2, 3); -- Сидоренко викладає Комп'ютерні мережі

SELECT * FROM lab_teacher_subjects ORDER BY teacher_id, subject_id;

-- 3. Сполучна таблиця N:M «Студенти — Дисципліни» із оцінками та статусом (lab_enrollments)
CREATE TABLE lab_enrollments (
    student_id integer NOT NULL
        REFERENCES lab_students(id)
        ON DELETE CASCADE,
    subject_id integer NOT NULL
        REFERENCES lab_subjects(id)
        ON DELETE RESTRICT,
    enrolled_at date NOT NULL DEFAULT CURRENT_DATE,
    grade integer CHECK (grade BETWEEN 0 AND 100),
    status enrollment_status NOT NULL DEFAULT 'enrolled',
    PRIMARY KEY (student_id, subject_id)
);

-- Наповнення академічних зарахувань студентів
INSERT INTO lab_enrollments (student_id, subject_id, grade, status)
VALUES
    (1, 1, 95, 'completed'),
    (1, 2, 88, 'completed'),
    (2, 1, 70, 'enrolled'),
    (3, 2, 92, 'completed'),
    (4, 1, 55, 'failed');

SELECT * FROM lab_enrollments ORDER BY student_id, subject_id;
