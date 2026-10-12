# Logistics - Система адресного складського обліку та логістики

Система управління складом (WMS) призначена для контролю надходження, адресного зберігання товарів у комірках та фіксації внутрішніх переміщень.

## Основний функціонал

- Ведення номенклатурного довідника товарів та їхніх параметрів
- Облік контактних даних постачальників
- Реєстрація накладних надходження (партій)
- Облік адресної структури складу (зони, стелажі, комірки)
- Контроль мінімальних залишків та запобігання дефіциту
- Оперативний облік поточних залишків у кожній комірці (`inventory_stock`)
- Аудит та фіксація внутрішніх переміщень товарів між комірками або списання

## Бізнес-правила системи

### 1. Товари та номенклатура (`product`)
- **Унікальність артикулу:** Кожен товар має унікальний артикул (`sku_code`).
- **Одиниці вимірювання:** За замовчуванням `unit = 'piece'`.
- **Контроль дефіциту:** Значення `min_stock_level >= 0`.

### 2. Постачальники та накладні (`supplier`, `supply_order`, `supply_item`)
- **Унікальність контактів:** Поле `email` є унікальним для кожного постачальника.
- **Статусна модель:** Накладна `supply_order` має статус: `draft`, `received` або `cancelled`.
- **Фіксація цін:** У `supply_item` зберігається закуплена кількість та ціна на момент приходу.

### 3. Адресне зберігання та переміщення (`warehouse_location`, `inventory_stock`, `inventory_movement`)
- **Унікальність комірки:** Поле `location_code` є унікальним, а поєднання `(zone, shelf_number)` формує складене обмеження унікальності.
- **Оперативні залишки:** Поточна наявність товару в комірці зберігається в таблиці `inventory_stock`. Пара `(product_id, location_id)` є унікальною.
- **Валідація переміщення:** Переміщення товару в ту саму комірку заборонено (`from_location_id IS DISTINCT FROM to_location_id`).

---

## Концептуальна ER-діаграма

```mermaid
erDiagram
    SUPPLIER ||--o{ SUPPLY_ORDER : "supplies"
    SUPPLY_ORDER ||--|{ SUPPLY_ITEM : "contains"
    PRODUCT ||--o{ SUPPLY_ITEM : "included_in"
    PRODUCT ||--o{ INVENTORY_STOCK : "has_stock_in"
    WAREHOUSE_LOCATION ||--o{ INVENTORY_STOCK : "holds_stock"
    PRODUCT ||--o{ INVENTORY_MOVEMENT : "moves"
    WAREHOUSE_LOCATION ||--o{ INVENTORY_MOVEMENT : "source_location"
    WAREHOUSE_LOCATION ||--o{ INVENTORY_MOVEMENT : "target_location"

    SUPPLIER {
        INT supplier_id PK
        VARCHAR company_name
        VARCHAR contact_person
        VARCHAR phone
        VARCHAR email UK
        TEXT address
    }

    PRODUCT {
        INT product_id PK
        VARCHAR sku_code UK
        VARCHAR name
        TEXT description
        VARCHAR unit
        INT min_stock_level
    }

    WAREHOUSE_LOCATION {
        INT location_id PK
        VARCHAR location_code UK
        VARCHAR zone
        VARCHAR shelf_number
        INT max_capacity
    }

    SUPPLY_ORDER {
        INT order_id PK
        VARCHAR order_number UK
        INT supplier_id FK
        TIMESTAMP supply_date
        NUMERIC total_cost
        VARCHAR status
    }

    SUPPLY_ITEM {
        INT item_id PK
        INT order_id FK
        INT product_id FK
        INT quantity
        NUMERIC unit_price
    }

    INVENTORY_STOCK {
        INT stock_id PK
        INT product_id FK
        INT location_id FK
        INT quantity
    }

    INVENTORY_MOVEMENT {
        INT movement_id PK
        INT product_id FK
        INT from_location_id FK
        INT to_location_id FK
        INT quantity
        TIMESTAMP movement_date
    }