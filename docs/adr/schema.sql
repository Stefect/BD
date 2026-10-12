DROP TABLE IF EXISTS inventory_movement CASCADE;
DROP TABLE IF EXISTS inventory_stock CASCADE;
DROP TABLE IF EXISTS supply_item CASCADE;
DROP TABLE IF EXISTS supply_order CASCADE;
DROP TABLE IF EXISTS warehouse_location CASCADE;
DROP TABLE IF EXISTS product CASCADE;
DROP TABLE IF EXISTS supplier CASCADE;

CREATE TABLE supplier (
    supplier_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_name VARCHAR(100) NOT NULL,
    contact_person VARCHAR(100) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    address TEXT NOT NULL
);

CREATE TABLE product (
    product_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku_code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    unit VARCHAR(20) NOT NULL DEFAULT 'piece',
    min_stock_level INT NOT NULL DEFAULT 0 CHECK (min_stock_level >= 0)
);

CREATE TABLE warehouse_location (
    location_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    location_code VARCHAR(50) NOT NULL UNIQUE,
    zone VARCHAR(50) NOT NULL,
    shelf_number VARCHAR(50) NOT NULL,
    max_capacity INT NOT NULL CHECK (max_capacity > 0),
    CONSTRAINT uk_zone_shelf UNIQUE (zone, shelf_number)
);

CREATE TABLE supply_order (
    order_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_number VARCHAR(50) NOT NULL UNIQUE,
    supplier_id INT NOT NULL REFERENCES supplier(supplier_id) ON DELETE RESTRICT,
    supply_date TIMESTAMP NOT NULL DEFAULT NOW(),
    total_cost NUMERIC(10, 2) NOT NULL DEFAULT 0.00 CHECK (total_cost >= 0),
    status VARCHAR(20) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'received', 'cancelled'))
);

CREATE TABLE supply_item (
    item_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id INT NOT NULL REFERENCES supply_order(order_id) ON DELETE CASCADE,
    product_id INT NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT,
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10, 2) NOT NULL CHECK (unit_price >= 0)
);

CREATE TABLE inventory_stock (
    stock_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id INT NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT,
    location_id INT NOT NULL REFERENCES warehouse_location(location_id) ON DELETE RESTRICT,
    quantity INT NOT NULL CHECK (quantity >= 0),
    CONSTRAINT uk_product_location UNIQUE (product_id, location_id)
);

CREATE TABLE inventory_movement (
    movement_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id INT NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT,
    from_location_id INT NOT NULL REFERENCES warehouse_location(location_id) ON DELETE RESTRICT,
    to_location_id INT REFERENCES warehouse_location(location_id) ON DELETE RESTRICT,
    quantity INT NOT NULL CHECK (quantity > 0),
    movement_date TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_different_locations CHECK (from_location_id IS DISTINCT FROM to_location_id)
);

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

INSERT INTO supply_order (order_number, supplier_id, total_cost, status) VALUES
('ORD-2026-01', 1, 105000.00, 'received'),
('ORD-2026-02', 3, 42000.00, 'received'),
('ORD-2026-03', 4, 18500.00, 'received'),
('ORD-2026-04', 2, 12000.00, 'draft'),
('ORD-2026-05', 5, 34000.00, 'cancelled');

INSERT INTO supply_item (order_id, product_id, quantity, unit_price) VALUES
(1, 1, 30, 2500.00),
(1, 2, 100, 300.00),
(2, 3, 500, 60.00),
(2, 4, 10, 1200.00),
(3, 5, 20, 925.00);

INSERT INTO inventory_stock (product_id, location_id, quantity) VALUES
(1, 1, 10),
(1, 3, 20),
(2, 2, 100),
(3, 3, 450),
(3, 4, 45);

INSERT INTO inventory_movement (product_id, from_location_id, to_location_id, quantity) VALUES
(1, 1, 3, 20),
(3, 3, 4, 50),
(3, 4, NULL, 5),
(2, 2, 1, 10),
(5, 5, 2, 5);