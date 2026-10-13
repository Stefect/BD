-- =====================================================================
-- Тести бізнес-правил для схеми logistics.
-- Запуск: після schema.sql. Усе виконується в одній транзакції і відкочується,
-- тому дані бази не змінюються.
-- Очікуваний результат: усі рядки виводу мають PASS. FAIL означає, що правило не спрацювало.
-- Негативний тест: операція має бути відхилена (PASS = помилка отримана).
-- =====================================================================

BEGIN;

-- R-08: переміщення понад залишок заблоковано
DO $$ BEGIN
    INSERT INTO inventory_movement (movement_type, product_id, from_location_id, to_location_id, quantity)
    VALUES ('transfer', 1, 1, 2, 1000);
    RAISE NOTICE 'FAIL T01: переміщення понад залишок пройшло';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS T01 (переміщення понад залишок): %', SQLERRM;
END $$;

-- R-08: переміщення в ту саму комірку заблоковано
DO $$ BEGIN
    INSERT INTO inventory_movement (movement_type, product_id, from_location_id, to_location_id, quantity)
    VALUES ('transfer', 1, 1, 1, 1);
    RAISE NOTICE 'FAIL T02: переміщення в ту саму комірку пройшло';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS T02 (та сама комірка): %', SQLERRM;
END $$;

-- R-09: списання не може мати комірку-отримувача
DO $$ BEGIN
    INSERT INTO inventory_movement (movement_type, product_id, from_location_id, to_location_id, quantity)
    VALUES ('write_off', 3, 4, 2, 1);
    RAISE NOTICE 'FAIL T03: списання з коміркою-отримувачем пройшло';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS T03 (списання з отримувачем): %', SQLERRM;
END $$;

-- R-10: журнал переміщень не можна змінювати
DO $$ BEGIN
    UPDATE inventory_movement SET quantity = 1 WHERE movement_id = 1;
    RAISE NOTICE 'FAIL T04: зміна переміщення пройшла';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS T04 (зміна переміщення): %', SQLERRM;
END $$;

-- R-10: журнал переміщень не можна видаляти
DO $$ BEGIN
    DELETE FROM inventory_movement WHERE movement_id = 1;
    RAISE NOTICE 'FAIL T05: видалення переміщення пройшло';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS T05 (видалення переміщення): %', SQLERRM;
END $$;

-- R-03: переповнення комірки заблоковано (LOC-C-1 місткість 300, у ній уже 45)
DO $$ BEGIN
    INSERT INTO inventory_movement (movement_type, product_id, from_location_id, to_location_id, quantity)
    VALUES ('transfer', 3, 3, 4, 300);
    RAISE NOTICE 'FAIL T06: переповнення комірки пройшло';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS T06 (переповнення комірки): %', SQLERRM;
END $$;

-- R-04: позиції отриманої накладної не можна змінювати
DO $$ BEGIN
    INSERT INTO supply_item (order_id, product_id, location_id, quantity, unit_price, batch_number)
    VALUES ((SELECT order_id FROM supply_order WHERE order_number = 'ORD-2026-01'), 3, 1, 1, 1.00, 'T');
    RAISE NOTICE 'FAIL T07: додавання позиції до отриманої накладної пройшло';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS T07 (зміна позицій отриманої накладної): %', SQLERRM;
END $$;

-- R-04: скасовану накладну не можна повернути в чернетку
DO $$ BEGIN
    UPDATE supply_order SET status = 'draft' WHERE order_number = 'ORD-2026-05';
    RAISE NOTICE 'FAIL T08: перехід із cancelled у draft пройшов';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS T08 (перехід з cancelled): %', SQLERRM;
END $$;

-- R-04: нова накладна створюється лише в статусі draft
DO $$ BEGIN
    INSERT INTO supply_order (order_number, supplier_id, status) VALUES ('T-09', 1, 'received');
    RAISE NOTICE 'FAIL T09: накладна створена одразу як received';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS T09 (створення в статусі received): %', SQLERRM;
END $$;

-- R-04: накладну без позицій не можна отримати
DO $$ BEGIN
    INSERT INTO supply_order (order_number, supplier_id) VALUES ('T-10', 1);
    UPDATE supply_order SET status = 'received' WHERE order_number = 'T-10';
    RAISE NOTICE 'FAIL T10: накладна без позицій отримана';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS T10 (отримання без позицій): %', SQLERRM;
END $$;

-- R-04: видаляти можна лише чернетку
DO $$ BEGIN
    DELETE FROM supply_order WHERE order_number = 'ORD-2026-01';
    RAISE NOTICE 'FAIL T11: видалення отриманої накладної пройшло';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS T11 (видалення отриманої накладної): %', SQLERRM;
END $$;

-- R-02: email унікальний без урахування регістру
DO $$ BEGIN
    INSERT INTO supplier (company_name, contact_person, phone, email, address)
    VALUES ('X', 'Y', '+380500000001', 'INFO@electro.ua', 'адреса');
    RAISE NOTICE 'FAIL T12: дубль email у іншому регістрі пройшов';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS T12 (дубль email у іншому регістрі): %', SQLERRM;
END $$;

-- R-02: телефон у форматі +380...
DO $$ BEGIN
    INSERT INTO supplier (company_name, contact_person, phone, email, address)
    VALUES ('X', 'Y', '380500000001', 'new@x.ua', 'адреса');
    RAISE NOTICE 'FAIL T13: телефон без знака + пройшов';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS T13 (формат телефону): %', SQLERRM;
END $$;

-- R-01: формат артикула
DO $$ BEGIN
    INSERT INTO product (sku_code, name, unit, min_stock_level) VALUES ('sku-1', 'X', 'piece', 0);
    RAISE NOTICE 'FAIL T14: артикул у нижньому регістрі пройшов';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS T14 (формат артикула): %', SQLERRM;
END $$;

-- R-01: допустимі одиниці виміру
DO $$ BEGIN
    INSERT INTO product (sku_code, name, unit, min_stock_level) VALUES ('SKU-X-1', 'X', 'bottle', 0);
    RAISE NOTICE 'FAIL T15: недопустима одиниця виміру пройшла';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS T15 (одиниця виміру): %', SQLERRM;
END $$;

-- R-05: кількість у позиції має бути додатною
DO $$ BEGIN
    INSERT INTO supply_item (order_id, product_id, location_id, quantity, unit_price, batch_number)
    VALUES ((SELECT order_id FROM supply_order WHERE order_number = 'ORD-2026-04'), 2, 1, 0, 1.00, 'T');
    RAISE NOTICE 'FAIL T16: позиція з нульовою кількістю пройшла';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS T16 (нульова кількість): %', SQLERRM;
END $$;

-- R-01: товар, що використовується, не можна видалити
DO $$ BEGIN
    DELETE FROM product WHERE product_id = 1;
    RAISE NOTICE 'FAIL T17: видалення використовуваного товару пройшло';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS T17 (видалення використовуваного товару): %', SQLERRM;
END $$;

-- R-05: сума накладної перераховується тригером при додаванні позиції
DO $$ DECLARE v NUMERIC; BEGIN
    INSERT INTO supply_order (order_number, supplier_id) VALUES ('T-18', 1);
    INSERT INTO supply_item (order_id, product_id, location_id, quantity, unit_price, batch_number)
    VALUES ((SELECT order_id FROM supply_order WHERE order_number = 'T-18'), 2, 1, 2, 10.00, 'T');
    SELECT total_cost INTO v FROM supply_order WHERE order_number = 'T-18';
    IF v = 20.00 THEN
        RAISE NOTICE 'PASS T18 (сума накладної перераховується): %', v;
    ELSE
        RAISE NOTICE 'FAIL T18: сума накладної = %, очікувалось 20.00', v;
    END IF;
END $$;

-- R-06: оприбуткування збільшує залишок у вказаній комірці
DO $$ DECLARE v INT; BEGIN
    INSERT INTO supply_order (order_number, supplier_id) VALUES ('T-19', 1);
    INSERT INTO supply_item (order_id, product_id, location_id, quantity, unit_price, batch_number)
    VALUES ((SELECT order_id FROM supply_order WHERE order_number = 'T-19'), 4, 1, 3, 10.00, 'T');
    UPDATE supply_order SET status = 'received' WHERE order_number = 'T-19';
    SELECT quantity INTO v FROM inventory_stock WHERE product_id = 4 AND location_id = 1;
    IF v = 3 THEN
        RAISE NOTICE 'PASS T19 (оприбуткування збільшує залишок): %', v;
    ELSE
        RAISE NOTICE 'FAIL T19: залишок після оприбуткування = %, очікувалось 3', v;
    END IF;
END $$;

ROLLBACK;
