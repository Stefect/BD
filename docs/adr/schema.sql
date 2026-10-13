-- =====================================================================
-- Logistics WMS: схема PostgreSQL (лабораторна робота 2)
-- Виконувати в базі logistics. Скрипт видаляє і створює об'єкти заново.
-- Документація: docs/adr/spec.md (вимоги R-01..R-13 і трасованість),
-- docs/adr/0001-database-design-decisions.md, docs/adr/0002-*.md,
-- тести бізнес-правил: docs/adr/tests.sql
-- =====================================================================

DROP VIEW IF EXISTS v_low_stock, v_stock_by_product, v_location_load CASCADE;
DROP TABLE IF EXISTS inventory_movement CASCADE;
DROP TABLE IF EXISTS inventory_stock CASCADE;
DROP TABLE IF EXISTS supply_item CASCADE;
DROP TABLE IF EXISTS supply_order CASCADE;
DROP TABLE IF EXISTS warehouse_location CASCADE;
DROP TABLE IF EXISTS product CASCADE;
DROP TABLE IF EXISTS supplier CASCADE;

-- =====================================================================
-- Таблиці
-- =====================================================================

-- Постачальник (R-02)
CREATE TABLE supplier (
    supplier_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_name VARCHAR(100) NOT NULL,
    contact_person VARCHAR(100) NOT NULL,
    phone VARCHAR(20) NOT NULL CHECK (phone ~ '^\+[0-9]{10,15}$'),
    email VARCHAR(100) NOT NULL CHECK (email LIKE '%_@_%'),
    address TEXT NOT NULL
);
-- Унікальність email без урахування регістру
CREATE UNIQUE INDEX uq_supplier_email_ci ON supplier (lower(email));

-- Товар (R-01)
CREATE TABLE product (
    product_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku_code VARCHAR(50) NOT NULL UNIQUE CHECK (sku_code ~ '^[A-Z0-9-]+$'),
    name VARCHAR(100) NOT NULL,
    description TEXT,
    unit VARCHAR(20) NOT NULL DEFAULT 'piece' CHECK (unit IN ('piece', 'kg', 'liter', 'box', 'pallet')),
    min_stock_level INT NOT NULL DEFAULT 0 CHECK (min_stock_level >= 0)
);

-- Комірка складу (R-03)
CREATE TABLE warehouse_location (
    location_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    location_code VARCHAR(50) NOT NULL UNIQUE CHECK (location_code ~ '^LOC-[A-Z0-9]+-[0-9]+$'),
    zone VARCHAR(50) NOT NULL,
    shelf_number VARCHAR(50) NOT NULL,
    max_capacity INT NOT NULL CHECK (max_capacity > 0),
    CONSTRAINT uk_zone_shelf UNIQUE (zone, shelf_number)
);

-- Накладна постачання (R-04)
CREATE TABLE supply_order (
    order_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_number VARCHAR(50) NOT NULL UNIQUE,
    supplier_id INT NOT NULL REFERENCES supplier(supplier_id) ON DELETE RESTRICT,
    supply_date TIMESTAMPTZ NOT NULL DEFAULT now(),
    total_cost NUMERIC(10, 2) NOT NULL DEFAULT 0.00 CHECK (total_cost >= 0),
    status VARCHAR(20) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'received', 'cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by VARCHAR(100) NOT NULL DEFAULT current_user
);

-- Позиція накладної, таблиця сполучення товар-накладна (R-05)
CREATE TABLE supply_item (
    order_id INT NOT NULL REFERENCES supply_order(order_id) ON DELETE CASCADE,
    product_id INT NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT,
    location_id INT NOT NULL REFERENCES warehouse_location(location_id) ON DELETE RESTRICT,
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10, 2) NOT NULL CHECK (unit_price >= 0),
    batch_number VARCHAR(50) NOT NULL,
    expiry_date DATE,
    CONSTRAINT pk_supply_item PRIMARY KEY (order_id, product_id)
);
CREATE INDEX ix_supply_item_product ON supply_item (product_id);
CREATE INDEX ix_supply_item_location ON supply_item (location_id);

-- Оперативні залишки товару в комірці (R-07), змінюють лише тригери
CREATE TABLE inventory_stock (
    product_id INT NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT,
    location_id INT NOT NULL REFERENCES warehouse_location(location_id) ON DELETE RESTRICT,
    quantity INT NOT NULL CHECK (quantity >= 0),
    CONSTRAINT pk_inventory_stock PRIMARY KEY (product_id, location_id)
);
CREATE INDEX ix_inventory_stock_location ON inventory_stock (location_id);

-- Переміщення і списання, журнал незмінний (R-08, R-09, R-10)
CREATE TABLE inventory_movement (
    movement_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    movement_type VARCHAR(20) NOT NULL CHECK (movement_type IN ('transfer', 'write_off')),
    product_id INT NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT,
    from_location_id INT NOT NULL REFERENCES warehouse_location(location_id) ON DELETE RESTRICT,
    to_location_id INT REFERENCES warehouse_location(location_id) ON DELETE RESTRICT,
    quantity INT NOT NULL CHECK (quantity > 0),
    reason VARCHAR(255),
    movement_date TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by VARCHAR(100) NOT NULL DEFAULT current_user,
    CONSTRAINT chk_different_locations CHECK (from_location_id IS DISTINCT FROM to_location_id),
    CONSTRAINT chk_movement_type_target CHECK (
        (movement_type = 'transfer' AND to_location_id IS NOT NULL)
        OR (movement_type = 'write_off' AND to_location_id IS NULL)
    )
);
CREATE INDEX ix_movement_product ON inventory_movement (product_id);
CREATE INDEX ix_movement_from ON inventory_movement (from_location_id);
CREATE INDEX ix_movement_to ON inventory_movement (to_location_id);

-- =====================================================================
-- Функції та тригери (бізнес-логіка, R-04..R-10)
-- =====================================================================

-- Змінює залишок товару в комірці, перевіряє невід'ємність і місткість комірки
CREATE OR REPLACE FUNCTION fn_adjust_stock(p_product INT, p_location INT, p_delta INT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    v_qty INT;
    v_total INT;
    v_max INT;
BEGIN
    INSERT INTO inventory_stock (product_id, location_id, quantity)
    VALUES (p_product, p_location, 0)
    ON CONFLICT (product_id, location_id) DO NOTHING;

    UPDATE inventory_stock
       SET quantity = quantity + p_delta
     WHERE product_id = p_product AND location_id = p_location
    RETURNING quantity INTO v_qty;

    IF v_qty < 0 THEN
        RAISE EXCEPTION 'Недостатньо товару % у комірці %: залишок був би %', p_product, p_location, v_qty;
    END IF;

    SELECT COALESCE(SUM(quantity), 0) INTO v_total
      FROM inventory_stock WHERE location_id = p_location;
    SELECT max_capacity INTO v_max
      FROM warehouse_location WHERE location_id = p_location;
    IF v_total > v_max THEN
        RAISE EXCEPTION 'Комірка % переповнена: зайнято %, місткість %', p_location, v_total, v_max;
    END IF;
END;
$$;

-- Накладна: створюється лише в статусі draft
CREATE OR REPLACE FUNCTION fn_order_insert_check()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status <> 'draft' THEN
        RAISE EXCEPTION 'Нова накладна має створюватися в статусі draft';
    END IF;
    RETURN NEW;
END;
$$;

-- Накладна: дозволені переходи з draft у received і з draft у cancelled, інші зміни заборонені
CREATE OR REPLACE FUNCTION fn_order_update_guard()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.status <> 'draft' AND (
           NEW.status IS DISTINCT FROM OLD.status
        OR NEW.total_cost IS DISTINCT FROM OLD.total_cost
        OR NEW.supplier_id IS DISTINCT FROM OLD.supplier_id
        OR NEW.order_number IS DISTINCT FROM OLD.order_number) THEN
        RAISE EXCEPTION 'Накладну % у статусі % не можна змінювати', OLD.order_id, OLD.status;
    END IF;

    IF OLD.status = 'draft' AND NEW.status = 'received'
       AND NOT EXISTS (SELECT 1 FROM supply_item WHERE order_id = OLD.order_id) THEN
        RAISE EXCEPTION 'Накладну % не можна отримати без позицій', OLD.order_id;
    END IF;

    RETURN NEW;
END;
$$;

-- Накладна: видаляти можна лише чернетку
CREATE OR REPLACE FUNCTION fn_order_delete_guard()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.status <> 'draft' THEN
        RAISE EXCEPTION 'Накладну % у статусі % не можна видалити', OLD.order_id, OLD.status;
    END IF;
    RETURN OLD;
END;
$$;

-- Оприбуткування: при переході з draft у received залишки збільшуються у вказаних комірках
CREATE OR REPLACE FUNCTION fn_order_receive()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT product_id, location_id, quantity
               FROM supply_item WHERE order_id = NEW.order_id
    LOOP
        PERFORM fn_adjust_stock(r.product_id, r.location_id, r.quantity);
    END LOOP;
    RETURN NULL;
END;
$$;

-- Позиції накладної: змінювати можна лише в чернетці
CREATE OR REPLACE FUNCTION fn_item_guard()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_order INT;
    v_status TEXT;
BEGIN
    v_order := CASE WHEN TG_OP = 'DELETE' THEN OLD.order_id ELSE NEW.order_id END;
    SELECT status INTO v_status FROM supply_order WHERE order_id = v_order;
    IF FOUND AND v_status <> 'draft' THEN
        RAISE EXCEPTION 'Позиції накладної % можна змінювати лише в статусі draft (зараз: %)', v_order, v_status;
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

-- Сума накладної завжди дорівнює сумі її позицій
CREATE OR REPLACE FUNCTION fn_item_total()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_order INT;
BEGIN
    v_order := CASE WHEN TG_OP = 'DELETE' THEN OLD.order_id ELSE NEW.order_id END;
    UPDATE supply_order o
       SET total_cost = (SELECT COALESCE(SUM(i.quantity * i.unit_price), 0)
                           FROM supply_item i WHERE i.order_id = v_order)
     WHERE o.order_id = v_order;
    RETURN NULL;
END;
$$;

-- Переміщення і списання змінюють залишки
CREATE OR REPLACE FUNCTION fn_movement_apply()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    PERFORM fn_adjust_stock(NEW.product_id, NEW.from_location_id, -NEW.quantity);
    IF NEW.to_location_id IS NOT NULL THEN
        PERFORM fn_adjust_stock(NEW.product_id, NEW.to_location_id, NEW.quantity);
    END IF;
    RETURN NULL;
END;
$$;

-- Журнал переміщень незмінний
CREATE OR REPLACE FUNCTION fn_movement_immutable()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'Записи про переміщення не можна змінювати або видаляти (аудит)';
END;
$$;

CREATE TRIGGER trg_order_insert BEFORE INSERT ON supply_order
    FOR EACH ROW EXECUTE FUNCTION fn_order_insert_check();
CREATE TRIGGER trg_order_update BEFORE UPDATE ON supply_order
    FOR EACH ROW EXECUTE FUNCTION fn_order_update_guard();
CREATE TRIGGER trg_order_delete BEFORE DELETE ON supply_order
    FOR EACH ROW EXECUTE FUNCTION fn_order_delete_guard();
CREATE TRIGGER trg_order_receive AFTER UPDATE OF status ON supply_order
    FOR EACH ROW WHEN (OLD.status = 'draft' AND NEW.status = 'received')
    EXECUTE FUNCTION fn_order_receive();

CREATE TRIGGER trg_item_guard BEFORE INSERT OR UPDATE OR DELETE ON supply_item
    FOR EACH ROW EXECUTE FUNCTION fn_item_guard();
CREATE TRIGGER trg_item_total AFTER INSERT OR UPDATE OR DELETE ON supply_item
    FOR EACH ROW EXECUTE FUNCTION fn_item_total();

CREATE TRIGGER trg_movement_apply AFTER INSERT ON inventory_movement
    FOR EACH ROW EXECUTE FUNCTION fn_movement_apply();
CREATE TRIGGER trg_movement_immutable BEFORE UPDATE OR DELETE ON inventory_movement
    FOR EACH ROW EXECUTE FUNCTION fn_movement_immutable();

-- =====================================================================
-- Представлення для звітів (R-11, R-12)
-- =====================================================================

-- Загальний залишок по товару і його мінімальний рівень
CREATE OR REPLACE VIEW v_stock_by_product AS
SELECT p.product_id, p.sku_code, p.name,
       COALESCE(SUM(s.quantity), 0) AS total_qty,
       p.min_stock_level
  FROM product p
  LEFT JOIN inventory_stock s ON s.product_id = p.product_id
 GROUP BY p.product_id, p.sku_code, p.name, p.min_stock_level;

-- Товари, залишок яких нижче мінімуму (потребують поповнення)
CREATE OR REPLACE VIEW v_low_stock AS
SELECT * FROM v_stock_by_product WHERE total_qty < min_stock_level;

-- Завантаженість комірок відносно місткості
CREATE OR REPLACE VIEW v_location_load AS
SELECT l.location_id, l.location_code, l.max_capacity,
       COALESCE(SUM(s.quantity), 0) AS used_qty
  FROM warehouse_location l
  LEFT JOIN inventory_stock s ON s.location_id = l.location_id
 GROUP BY l.location_id, l.location_code, l.max_capacity;

-- =====================================================================
-- Тестові дані (INSERT у порядку батьківських таблиць)
-- =====================================================================

INSERT INTO supplier (company_name, contact_person, phone, email, address) VALUES
('ТОВ ЕлектроПостач', 'Олексій Коваленко', '+380441112233', 'info@electro.ua', 'м. Київ, вул. Польова, 21'),
('ПП Логістік Плюс', 'Марія Бондаренко', '+380502223344', 'sales@logplus.com', 'м. Львів, вул. Зелена, 105'),
('ТОВ КабельТрейд', 'Дмитро Мельник', '+380673334455', 'contact@cabletrade.ua', 'м. Дніпро, вул. Будівельна, 4'),
('ПрАТ ТехноСвіт', 'Ірина Ткаченко', '+380634445566', 'support@technosvit.ua', 'м. Харків, просп. Науки, 40'),
('ТОВ Мережні Рішення', 'Василь Шевченко', '+380445556677', 'net@solutions.ua', 'м. Київ, вул. Стецена, 12');

INSERT INTO product (sku_code, name, description, unit, min_stock_level) VALUES
('SKU-UTP-5E', 'Кабель вита пара UTP Cat5e', 'Бухта 305м', 'box', 10),
('SKU-RJ45-100', 'Конектори RJ-45', 'Упаковка 100 шт', 'box', 25),
('SKU-PATCH-1M', 'Патчкорд UTP 1м', 'Мережевий кабель', 'piece', 50),
('SKU-ROUTER-AC', 'Маршрутизатор Wi-Fi AC1200', 'Двохдіапазонний роутер', 'piece', 5),
('SKU-SWITCH-8P', 'Комутатор 8 портів Gigabit', 'Некерований комутатор', 'piece', 8);

INSERT INTO warehouse_location (location_code, zone, shelf_number, max_capacity) VALUES
('LOC-A-1', 'Зона А', 'Стелаж 1', 500),
('LOC-A-2', 'Зона А', 'Стелаж 2', 500),
('LOC-B-1', 'Зона Б', 'Стелаж 1', 2000),
('LOC-C-1', 'Зона В', 'Стелаж 1', 300),
('LOC-D-1', 'Зона Г', 'Стелаж 1', 100);

-- Накладні створюються як чернетки, позиції додаються до переходу в статус received
INSERT INTO supply_order (order_number, supplier_id) VALUES
('ORD-2026-01', 1),
('ORD-2026-02', 3),
('ORD-2026-03', 4),
('ORD-2026-04', 2),
('ORD-2026-05', 5);

-- Позиції: товар, комірка приймання, партія, термін придатності
INSERT INTO supply_item (order_id, product_id, location_id, quantity, unit_price, batch_number, expiry_date) VALUES
((SELECT order_id FROM supply_order WHERE order_number = 'ORD-2026-01'), 1, 1, 30, 2500.00, 'P-2026-0101', NULL),
((SELECT order_id FROM supply_order WHERE order_number = 'ORD-2026-01'), 2, 2, 100, 300.00, 'P-2026-0101', '2027-12-31'),
((SELECT order_id FROM supply_order WHERE order_number = 'ORD-2026-02'), 3, 3, 500, 60.00, 'P-2026-0202', NULL),
((SELECT order_id FROM supply_order WHERE order_number = 'ORD-2026-02'), 4, 5, 10, 1200.00, 'P-2026-0202', '2028-06-30'),
((SELECT order_id FROM supply_order WHERE order_number = 'ORD-2026-03'), 5, 5, 20, 925.00, 'P-2026-0303', NULL),
((SELECT order_id FROM supply_order WHERE order_number = 'ORD-2026-04'), 3, 3, 200, 60.00, 'P-2026-0404', NULL),
((SELECT order_id FROM supply_order WHERE order_number = 'ORD-2026-05'), 5, 5, 40, 850.00, 'P-2026-0505', NULL);

-- Оприбуткування: перехід з draft у received (залишки збільшуються тригером)
UPDATE supply_order SET status = 'received'
 WHERE order_number IN ('ORD-2026-01', 'ORD-2026-02', 'ORD-2026-03');

-- Скасування: перехід з draft у cancelled (залишки не змінюються)
UPDATE supply_order SET status = 'cancelled' WHERE order_number = 'ORD-2026-05';

-- Переміщення і списання (залишки оновлюються тригером; журнал незмінний)
INSERT INTO inventory_movement (movement_type, product_id, from_location_id, to_location_id, quantity, reason) VALUES
('transfer', 1, 1, 3, 20, 'Поповнення комірки LOC-B-1'),
('transfer', 3, 3, 4, 50, 'Перенесення на LOC-C-1'),
('write_off', 3, 4, NULL, 5, 'Пошкодження упаковки'),
('transfer', 2, 2, 1, 10, 'Перенесення на LOC-A-1'),
('transfer', 5, 5, 2, 5, 'Перенесення на LOC-A-2');

-- =====================================================================
-- Перевірка результату
-- =====================================================================

SELECT * FROM supplier;
SELECT * FROM product;
SELECT * FROM warehouse_location;
SELECT * FROM supply_order;
SELECT * FROM supply_item;
SELECT * FROM inventory_stock;
SELECT * FROM inventory_movement;
SELECT * FROM v_stock_by_product;
SELECT * FROM v_location_load;

-- Сума позицій збігається з total_cost накладної (очікується 0 рядків)
SELECT o.order_id, o.total_cost, SUM(i.quantity * i.unit_price) AS items_total
FROM supply_order o
JOIN supply_item i ON i.order_id = o.order_id
GROUP BY o.order_id, o.total_cost
HAVING o.total_cost <> SUM(i.quantity * i.unit_price);

-- Надходження (received) = поточні залишки + списання (очікується 0 рядків)
WITH received AS (
    SELECT i.product_id, SUM(i.quantity) AS qty
    FROM supply_item i JOIN supply_order o ON o.order_id = i.order_id
    WHERE o.status = 'received'
    GROUP BY i.product_id
),
stock AS (
    SELECT product_id, SUM(quantity) AS qty FROM inventory_stock GROUP BY product_id
),
written_off AS (
    SELECT product_id, SUM(quantity) AS qty
    FROM inventory_movement WHERE to_location_id IS NULL GROUP BY product_id
)
SELECT COALESCE(r.product_id, s.product_id) AS product_id,
       COALESCE(r.qty, 0) AS received_qty,
       COALESCE(s.qty, 0) AS stock_qty,
       COALESCE(w.qty, 0) AS written_off_qty
FROM received r
FULL JOIN stock s ON s.product_id = r.product_id
LEFT JOIN written_off w ON w.product_id = COALESCE(r.product_id, s.product_id)
WHERE COALESCE(r.qty, 0) <> COALESCE(s.qty, 0) + COALESCE(w.qty, 0);

-- Товари нижче мінімального залишку (очікується 0 рядків у поточних даних)
SELECT * FROM v_low_stock;
