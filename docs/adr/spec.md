# Специфікація бази даних WMS (Warehouse Management System)

## Сутності та атрибути

- **Постачальник (Supplier):**
  - `supplier_id`: унікальний ідентифікатор (PK, INT GENERATED ALWAYS AS IDENTITY)
  - `company_name`: назва компанії
  - `contact_person`: ім'я та прізвище контактної особи
  - `phone`: контактний номер телефону
  - `email`: електронна пошта (UNIQUE)
  - `address`: адреса

- **Товар (Product):**
  - `product_id`: унікальний ідентифікатор (PK, INT GENERATED ALWAYS AS IDENTITY)
  - `sku_code`: артикул товару (UNIQUE)
  - `name`: назва товару
  - `description`: опис
  - `unit`: одиниця вимірювання (DEFAULT 'piece')
  - `min_stock_level`: мінімальний поріг залишку (CHECK >= 0)

- **Локація складу (WarehouseLocation):**
  - `location_id`: унікальний ідентифікатор комірки (PK, INT GENERATED ALWAYS AS IDENTITY)
  - `location_code`: код адреси комірки (UNIQUE)
  - `zone`: зона складу
  - `shelf_number`: номер стелажа/полиці
  - `max_capacity`: максимальна місткість (CHECK > 0)
  - *Обмеження:* складена унікальність `(zone, shelf_number)`

- **Накладна постачання (SupplyOrder):**
  - `order_id`: унікальний ідентифікатор (PK, INT GENERATED ALWAYS AS IDENTITY)
  - `order_number`: номер накладної (UNIQUE)
  - `supplier_id`: посилання на постачальника (FK -> supplier)
  - `supply_date`: дата надходження (DEFAULT NOW())
  - `total_cost`: загальна вартість (CHECK >= 0)
  - `status`: статус ('draft', 'received', 'cancelled')

- **Позиція накладної (SupplyItem):**
  - `item_id`: унікальний ідентифікатор позиції (PK, INT GENERATED ALWAYS AS IDENTITY)
  - `order_id`: посилання на накладну (FK -> supply_order ON DELETE CASCADE)
  - `product_id`: посилання на товар (FK -> product)
  - `quantity`: закуплена кількість (CHECK > 0)
  - `unit_price`: ціна за одиницю (CHECK >= 0)

- **Оперативні залишки (InventoryStock):**
  - `stock_id`: унікальний ідентифікатор запису залишку (PK, INT GENERATED ALWAYS AS IDENTITY)
  - `product_id`: посилання на товар (FK -> product)
  - `location_id`: посилання на комірку (FK -> warehouse_location)
  - `quantity`: поточна кількість товару в цій комірці (CHECK >= 0)
  - *Обмеження:* складена унікальність `(product_id, location_id)`

- **Внутрішнє переміщення (InventoryMovement):**
  - `movement_id`: унікальний ідентифікатор операції (PK, INT GENERATED ALWAYS AS IDENTITY)
  - `product_id`: посилання на товар (FK -> product)
  - `from_location_id`: комірка-відправник (FK -> warehouse_location)
  - `to_location_id`: комірка-отримувач (FK -> warehouse_location, NULL при списанні)
  - `quantity`: переміщена кількість (CHECK > 0)
  - `movement_date`: дата та час операції (DEFAULT NOW())

## Припущення та правила

1. Усі первинні ключі реалізовано через автоінкрементний тип `INT GENERATED ALWAYS AS IDENTITY` згідно зі стандартом SQL:2003.
2. Для швидкого отримання актуальних залишків без важкої агрегації історії виділено окрему таблицю `inventory_stock` (операційний стан залишків).
3. Переміщення в ту саму комірку заборонено обмеженням `CHECK (from_location_id IS DISTINCT FROM to_location_id)`.