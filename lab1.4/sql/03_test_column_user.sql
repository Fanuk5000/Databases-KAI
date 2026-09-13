-- 03_test_column_user.sql
-- Тестування доступу під обмеженою роллю column_user

-- 1. Перемикання контексту сесії на роль column_user та перевірка читання
SET ROLE column_user;
SELECT current_user, name, rating FROM lab_columns.students;

-- 2. Дозволена модифікація стовпця name
UPDATE lab_columns.students
SET name = 'Denis'
WHERE id = 1
RETURNING *;

-- 3. Заборонена модифікація стовпця rating (викличе ERROR: 42501: permission denied for table students)
-- UPDATE lab_columns.students
-- SET rating = 87
-- WHERE id = 1;

-- 4. Повернення до початкової ролі сесії
RESET ROLE;
