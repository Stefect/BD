# Logistics - Система адресного складського обліку та логістики

## Вимоги

- Ведення номенклатурного довідника товарів
- Облік контактних даних постачальників
- Реєстрація накладних надходження (партій)
- Облік адресної структури складу (зони, стелажі, полиці)
- Контроль мінімальних залишків та запобігання дефіциту
- Фіксація внутрішніх переміщень товарів між комірками

## Бізнес-правила системи

### Товари та номенклатура (Products)
* **Унікальність артикулу:** Кожен товар повинен мати глобально унікальний артикул (`sku_code`).
* **Одиниці вимірювання:** Значення `unit` визначається з переліку (`piece`, `kg`, `liter`, `box`, `pallet`).
* **Контроль дефіциту:** Значення `min_stock_level` не може бути меншим за 0. Якщо сумарний залишок товару на всіх локаціях стає меншим або рівним `min_stock_level`, система маркує позицію як критичну.

### Постачальники та накладні (Suppliers & Supply Orders)
* **Унікальність контактів:** Поле `email` та код компанії постачальника є унікальними в системі.
* **Статусна модель накладної:** Накладна `SupplyOrder` має статус із фіксованого списку: `draft`, `received`, `cancelled`.
* **Розрахунок вартості:** Поле `total_cost` розраховується автоматично як сума вартості всіх доданих позицій (`quantity * unit_price`).

### Адресне зберігання та переміщення (Warehouse & Movements)
* **Унікальність локації:** Поєднання полів `zone` та `shelf_number` формує унікальний ідентифікатор фізичної комірки.
* **Обмеження місткості:** Сумарна кількість одиниць товару, закріплених за коміркою, не може перевищувати `max_capacity`.
* **Валідація переміщення:** При створенні запису `InventoryMovement` вихідна локація (`from_location_id`) та кінцева локація (`to_location_id`) не можуть бути ідентичними.
* **Мінімальний обсяг операцій:** Кількість товару в накладній та в переміщенні повинна бути строго більшою за 0 (`quantity > 0`).

---

## Концептуальна ER-діаграма

```mermaid
erDiagram
    SUPPLIER ||--o{ SUPPLY_ORDER : "supplies"
    SUPPLY_ORDER ||--|{ SUPPLY_ITEM : "contains"
    PRODUCT ||--o{ SUPPLY_ITEM : "included_in"
    WAREHOUSE_LOCATION ||--o{ SUPPLY_ITEM : "stores"
    PRODUCT ||--o{ INVENTORY_MOVEMENT : "moves"
    WAREHOUSE_LOCATION ||--o{ INVENTORY_MOVEMENT : "source_location"
    WAREHOUSE_LOCATION ||--o{ INVENTORY_MOVEMENT : "target_location"

    SUPPLIER {
        UUID id PK
        TEXT company_name
        TEXT contact_person
        TEXT phone
        TEXT email UK
        TEXT address
    }

    SUPPLY_ORDER {
        UUID id PK
        TEXT order_number UK
        UUID supplier_id FK
        TIMESTAMP supply_date
        NUMERIC total_cost
        ENUM status "draft/received/cancelled"
    }

    SUPPLY_ITEM {
        BIGSERIAL id PK
        UUID supply_id FK
        UUID product_id FK
        UUID location_id FK
        INTEGER quantity
        NUMERIC unit_price
    }

    PRODUCT {
        UUID id PK
        VARCHAR(50) sku_code UK
        VARCHAR(150) name
        TEXT description
        ENUM unit "piece/kg/liter/box/pallet"
        INTEGER min_stock_level
    }

    WAREHOUSE_LOCATION {
        UUID id PK
        VARCHAR(50) location_code UK
        VARCHAR(50) zone
        VARCHAR(50) shelf_number
        INTEGER max_capacity
    }

    INVENTORY_MOVEMENT {
        BIGSERIAL id PK
        UUID product_id FK
        UUID from_location_id FK
        UUID to_location_id FK
        INTEGER quantity
        TIMESTAMP movement_date
    }