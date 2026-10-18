-- Лабораторна робота 3: Маніпулювання даними SQL (OLTP)
-- Запускати після docs/adr/schema.sql. Повторний запуск без перестворення схеми впаде на UNIQUE.
-- Блок в кінці (очікувана помилка) виконувати окремо.

SELECT * FROM supplier;
SELECT * FROM product;
SELECT * FROM warehouse_location;
SELECT * FROM supply_order;


-- 1. SELECT

SELECT supplier_id, company_name, phone, email
FROM supplier;

SELECT sku_code, name, min_stock_level
FROM product
WHERE unit = 'box';

SELECT sku_code, name
FROM product
WHERE name ILIKE '%кабель%';

SELECT order_number, total_cost, status
FROM supply_order
WHERE total_cost > 20000
ORDER BY total_cost DESC;

SELECT order_number, status, supply_date
FROM supply_order
WHERE status IN ('draft', 'cancelled');

SELECT order_id, product_id, batch_number
FROM supply_item
WHERE expiry_date IS NULL;

SELECT order_id, product_id
FROM supply_item
WHERE expiry_date = NULL;

SELECT order_id, product_id, unit_price
FROM supply_item
WHERE unit_price BETWEEN 300 AND 1000
ORDER BY unit_price;

SELECT location_code, zone, max_capacity
FROM warehouse_location
ORDER BY max_capacity DESC, location_code
LIMIT 3;

SELECT
    count(*)                                           AS total_orders,
    count(*) FILTER (WHERE status = 'received')        AS received_orders,
    sum(total_cost) FILTER (WHERE status = 'received') AS received_sum
FROM supply_order;

SELECT sum(quantity) AS total_qty
FROM inventory_stock
WHERE product_id = (SELECT product_id FROM product WHERE sku_code = 'SKU-PATCH-1M');

SELECT DISTINCT created_by
FROM inventory_movement;

SELECT movement_id, product_id, from_location_id, quantity, reason
FROM inventory_movement
WHERE to_location_id IS NULL;

SELECT movement_id, movement_type, quantity, reason, movement_date
FROM inventory_movement
ORDER BY movement_date, movement_id;


-- 2. INSERT

INSERT INTO supplier (company_name, contact_person, phone, email, address)
VALUES ('ТОВ СвітлоМережа', 'Наталія Гриценко', '+380501239876',
        'order@svitlomerezha.ua', 'м. Одеса, вул. Портова, 7')
RETURNING supplier_id, company_name;

INSERT INTO product (sku_code, name, description, unit, min_stock_level)
VALUES
    ('SKU-SFP-10G',  'Модуль SFP 10G',          'Оптичний трансівер',   'piece', 15),
    ('SKU-PDU-8',    'Блок розеток 8 гнізд',    'З вимикачем',          'piece',  4),
    ('SKU-TEST-DEL', 'Тестовий товар',          NULL,                   'piece',  0);

INSERT INTO warehouse_location (location_code, zone, shelf_number, max_capacity)
VALUES ('LOC-E-1', 'Зона Д', 'Стелаж 1', 250);

INSERT INTO supply_order (order_number, supplier_id)
VALUES ('ORD-2026-06',
        (SELECT supplier_id FROM supplier WHERE email = 'order@svitlomerezha.ua'))
RETURNING order_id, order_number, status;

INSERT INTO supply_item (order_id, product_id, location_id, quantity, unit_price, batch_number, expiry_date)
VALUES
    ((SELECT order_id FROM supply_order WHERE order_number = 'ORD-2026-06'),
     (SELECT product_id FROM product WHERE sku_code = 'SKU-SFP-10G'),
     (SELECT location_id FROM warehouse_location WHERE location_code = 'LOC-E-1'),
     20, 1450.00, 'P-2026-0606', '2028-01-31'),
    ((SELECT order_id FROM supply_order WHERE order_number = 'ORD-2026-06'),
     (SELECT product_id FROM product WHERE sku_code = 'SKU-PDU-8'),
     (SELECT location_id FROM warehouse_location WHERE location_code = 'LOC-E-1'),
     30, 320.00, 'P-2026-0606', NULL);

-- Суму накладної БД не перераховує автоматично (див. docs/adr/spec.md, розд. 4)
UPDATE supply_order
SET total_cost = (
    SELECT sum(quantity * unit_price)
    FROM supply_item
    WHERE order_id = (SELECT order_id FROM supply_order WHERE order_number = 'ORD-2026-06')
)
WHERE order_number = 'ORD-2026-06'
RETURNING order_number, total_cost;

INSERT INTO supplier (company_name, contact_person, phone, email, address)
VALUES ('ТОВ Мережні Рішення', 'Василь Шевченко', '+380445556677',
        'net@solutions.ua', 'м. Київ, вул. Стецена, 12')
ON CONFLICT (email) DO NOTHING;


-- 3. UPDATE

SELECT product_id, sku_code, min_stock_level
FROM product
WHERE sku_code = 'SKU-ROUTER-AC';

UPDATE product
SET min_stock_level = 6,
    description = 'Двохдіапазонний роутер AC1200'
WHERE sku_code = 'SKU-ROUTER-AC'
RETURNING product_id, sku_code, min_stock_level;

UPDATE supplier
SET address = 'м. Львів, вул. Зелена, 105, офіс 2'
WHERE email = 'sales@logplus.com'
RETURNING supplier_id, company_name, address;

-- Умова status = 'draft' потрібна: БД не контролює переходи статусів накладної
UPDATE supply_order
SET status = 'cancelled'
WHERE order_number = 'ORD-2026-04'
  AND status = 'draft'
RETURNING order_id, order_number, status;

BEGIN;

UPDATE supply_order
SET status = 'received'
WHERE order_number = 'ORD-2026-06'
  AND status = 'draft'
RETURNING order_id, order_number, status;
-- Має повернутися 1 рядок. Якщо 0 - ROLLBACK замість COMMIT.

INSERT INTO inventory_stock (product_id, location_id, quantity)
SELECT product_id, location_id, quantity
FROM supply_item
WHERE order_id = (SELECT order_id FROM supply_order WHERE order_number = 'ORD-2026-06')
ON CONFLICT (product_id, location_id)
DO UPDATE SET quantity = inventory_stock.quantity + excluded.quantity;

COMMIT;

BEGIN;

INSERT INTO inventory_movement (movement_type, product_id, from_location_id, to_location_id, quantity, reason, created_by)
VALUES
    ('transfer',
     (SELECT product_id FROM product WHERE sku_code = 'SKU-SFP-10G'),
     (SELECT location_id FROM warehouse_location WHERE location_code = 'LOC-E-1'),
     (SELECT location_id FROM warehouse_location WHERE location_code = 'LOC-A-1'),
     5, 'Поповнення комірки LOC-A-1', 'Петренко А.'),
    ('write_off',
     (SELECT product_id FROM product WHERE sku_code = 'SKU-PDU-8'),
     (SELECT location_id FROM warehouse_location WHERE location_code = 'LOC-E-1'),
     NULL,
     2, 'Пошкоджена упаковка', 'Іваненко О.');

UPDATE inventory_stock
SET quantity = quantity - 5
WHERE product_id = (SELECT product_id FROM product WHERE sku_code = 'SKU-SFP-10G')
  AND location_id = (SELECT location_id FROM warehouse_location WHERE location_code = 'LOC-E-1');

UPDATE inventory_stock
SET quantity = quantity - 2
WHERE product_id = (SELECT product_id FROM product WHERE sku_code = 'SKU-PDU-8')
  AND location_id = (SELECT location_id FROM warehouse_location WHERE location_code = 'LOC-E-1');

INSERT INTO inventory_stock (product_id, location_id, quantity)
VALUES (
    (SELECT product_id FROM product WHERE sku_code = 'SKU-SFP-10G'),
    (SELECT location_id FROM warehouse_location WHERE location_code = 'LOC-A-1'),
    5
)
ON CONFLICT (product_id, location_id)
DO UPDATE SET quantity = inventory_stock.quantity + excluded.quantity;

COMMIT;

SELECT * FROM inventory_stock ORDER BY product_id, location_id;

-- Демо: UPDATE без WHERE змінює всі рядки; ROLLBACK повертає їх назад
BEGIN;
UPDATE warehouse_location SET max_capacity = 1;
SELECT location_code, max_capacity FROM warehouse_location;
ROLLBACK;
SELECT location_code, max_capacity FROM warehouse_location;


-- 4. DELETE

SELECT product_id, sku_code FROM product WHERE sku_code = 'SKU-TEST-DEL';

DELETE FROM product
WHERE sku_code = 'SKU-TEST-DEL'
RETURNING product_id, sku_code;

-- Спочатку дочірні рядки (supply_item), потім батьківський (supply_order)
BEGIN;

SELECT order_id, product_id FROM supply_item
WHERE order_id = (SELECT order_id FROM supply_order
                  WHERE order_number = 'ORD-2026-04' AND status = 'cancelled');

DELETE FROM supply_item
WHERE order_id = (SELECT order_id FROM supply_order
                  WHERE order_number = 'ORD-2026-04' AND status = 'cancelled')
RETURNING order_id, product_id;

DELETE FROM supply_order
WHERE order_number = 'ORD-2026-04'
  AND status = 'cancelled'
RETURNING order_id, order_number;

COMMIT;

-- Демо: DELETE з WHERE і ROLLBACK
BEGIN;
DELETE FROM inventory_movement WHERE created_by = 'Петренко А.';
ROLLBACK;
SELECT movement_id, reason FROM inventory_movement WHERE created_by = 'Петренко А.';


-- 5. Фінальна перевірка

SELECT * FROM supplier;
SELECT * FROM product;
SELECT * FROM warehouse_location;
SELECT * FROM supply_order;
SELECT * FROM supply_item;
SELECT * FROM inventory_stock ORDER BY product_id, location_id;
SELECT * FROM inventory_movement ORDER BY movement_id;


-- Очікувана помилка (виконувати окремо): FK блокує видалення постачальника з накладними
-- DELETE FROM supplier WHERE email = 'info@electro.ua';
