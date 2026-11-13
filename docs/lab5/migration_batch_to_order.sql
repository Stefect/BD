-- =====================================================================
-- Лабораторна 5: декомпозиція для усунення часткової залежності (2НФ)
-- Лише конструкції з лекцій: ALTER TABLE (лекція 9), скалярний підзапит (лекція 7),
-- BEGIN/COMMIT (лекція 10), DDL і дані в одній міграції (лекція 9).
--
-- Застосовувати ТІЛЬКИ якщо правило "одна партія на накладну" підтверджено.
-- Крок 0 (вручну, перед запуском): має повернути 0 рядків.
--   SELECT order_id FROM supply_item GROUP BY order_id HAVING COUNT(DISTINCT batch_number) > 1;
-- =====================================================================

BEGIN;

-- 1. Додаємо batch_number до накладної (безпечна операція, лекція 9)
ALTER TABLE supply_order ADD COLUMN batch_number VARCHAR(50);

-- 2. Переносимо партію з позицій у накладну.
--    Скалярний підзапит повертає одне значення, бо за кроком 0 партія в накладній одна.
UPDATE supply_order o
SET batch_number = (
    SELECT DISTINCT i.batch_number
    FROM supply_item i
    WHERE i.order_id = o.order_id
);

-- 3. Тепер значення обов'язкове (перевірка всіх рядків, лекція 9)
ALTER TABLE supply_order ALTER COLUMN batch_number SET NOT NULL;

-- 4. Прибираємо залежний атрибут з таблиці позицій (безпечна операція, лекція 9)
ALTER TABLE supply_item DROP COLUMN batch_number;

COMMIT;

-- Перевірка після міграції:
-- SELECT order_number, batch_number FROM supply_order ORDER BY order_id;
