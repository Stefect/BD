# Лабораторна робота 5: Нормалізація бази даних

**База:** `logistics` (схема лабораторної 2, `docs/adr/schema.sql`)
**Скрипти:** `docs/lab5/lab5_normalization.sql` (перевірка функціональних залежностей), `docs/lab5/migration_batch_to_order.sql` (фінальна декомпозиція)
**Попередні роботи:** `docs/lab2_report.docx`, `docs/adr/spec.md`, `docs/lab3/lab3_report.md`

## 1. Мета

Пройти всі три кроки нормалізації (1НФ, 2НФ, 3НФ) для даних постачань `logistics`: від ненормалізованої накладної до схеми лабораторної 2 і її уточнення. Для кожного кроку вказати функціональні залежності, порушення і декомпозицію.

## 2. Ненормалізована форма

Схема лабораторної 2 вже є результатом проектування, тому почнемо з того, як накладна існує в документі постачання: один рядок на накладну, а позиції товарів - повторюваними групами. У даних лабораторної є до 2 позицій на накладну.

Таблиця `U0` (ненормалізована):

| Група | Атрибути |
|---|---|
| Накладна | `order_number`, `supplier_id`, `company_name`, `supplier_address`, `supply_date`, `total_cost`, `status`, `batch_number` |
| Позиція 1 | `sku_code_1`, `product_name_1`, `unit_1`, `location_code_1`, `zone_1`, `quantity_1`, `unit_price_1`, `expiry_date_1` |
| Позиція 2 | `sku_code_2`, `product_name_2`, `unit_2`, `location_code_2`, `zone_2`, `quantity_2`, `unit_price_2`, `expiry_date_2` |

Для накладних з однією позицією група позиції 2 порожня (NULL).

Порушення вже в цій формі: повторювана група позицій (`*_1`, `*_2`) - це порушення 1НФ.

## 3. Функціональні залежності U0

Для однієї позиції ключ таблиці - `(order_number, sku_code)`. Групи `*_2` мають ті самі залежності, що й `*_1`.

| Залежність | Тип |
|---|---|
| `order_number → supplier_id, company_name, supplier_address, supply_date, total_cost, status, batch_number` | часткова (від частини ключа) |
| `sku_code → product_name, unit` | часткова (від частини ключа) |
| `(order_number, sku_code) → location_code, quantity, unit_price, expiry_date` | повна |
| `location_code → zone` | транзитивна: `(order_number, sku_code) → location_code → zone` |
| `supplier_id → company_name, supplier_address` | транзитивна: `order_number → supplier_id → company_name` |

## 4. Крок 1: 1НФ

**Порушення:** повторювані групи позицій. Атрибути `sku_code_1`, `sku_code_2` і т.д. є однією і тією самою властивістю, записаною кілька разів.

**Рішення:** винести кожну позицію в окремий рядок.

Таблиця `R1` (1НФ):

`R1(order_number, sku_code, supplier_id, company_name, supplier_address, supply_date, total_cost, status, batch_number, product_name, unit, location_code, zone, quantity, unit_price, expiry_date)`

Ключ: `(order_number, sku_code)`. У даних 7 рядків (2 + 2 + 1 + 1 + 1).

Після цього всі атрибути атомарні, повторюваних груп немає. Таблиця в 1НФ, але не в 2НФ і не в 3НФ (залежності з розд. 3 лишаються).

## 5. Крок 2: 2НФ

**Порушення:** часткові залежності від частини складеного ключа `(order_number, sku_code)`:
- `order_number → supplier_id, company_name, supplier_address, supply_date, total_cost, status, batch_number`;
- `sku_code → product_name, unit`.

Аномалії:
- **Оновлення:** назва товару зберігається в кожній накладній, де він є; зміна назви вимагає оновлення всіх таких рядків.
- **Вставка:** неможливо додати товар, якого ще немає в накладній.
- **Видалення:** видалення останньої накладної з товаром стирає інформацію про сам товар.
- **Надмірність:** `batch_number` і `total_cost` повторюються в кожній позиції накладної.

**Рішення:** винести часткові залежності в окремі таблиці.

- `ORDER(order_number PK, supplier_id, company_name, supplier_address, supply_date, total_cost, status, batch_number)`
- `PRODUCT(sku_code PK, product_name, unit)`
- `ORDER_ITEM(order_number, sku_code PK, location_code, zone, quantity, unit_price, expiry_date)`, ключ `(order_number, sku_code)`

Після декомпозиції кожен неключовий атрибут залежить від повного ключа своєї таблиці. Таблиці `ORDER` і `ORDER_ITEM` ще містять транзитивні залежності, які розв'язуємо на кроці 3.

## 6. Крок 3: 3НФ

**Порушення 1:** у `ORDER` є `supplier_id → company_name, supplier_address`. Атрибути постачальника залежать від `order_number` транзитивно через `supplier_id`.

**Порушення 2:** у `ORDER_ITEM` є `location_code → zone`. Зона залежить від `(order_number, sku_code)` транзитивно через комірку.

**Рішення:** винести транзитивні залежності в окремі таблиці.

- `SUPPLIER(supplier_id PK, company_name, supplier_address)`
- `ORDER(order_number PK, supplier_id FK, supply_date, total_cost, status, batch_number)`
- `LOCATION(location_code PK, zone)`
- `ORDER_ITEM(order_number FK, sku_code FK, location_code FK, quantity, unit_price, expiry_date)`, ключ `(order_number, sku_code)`
- `PRODUCT(sku_code PK, product_name, unit)` - без змін

Перевірка 3НФ: у кожній таблиці кожен неключовий атрибут залежить від ключа безпосередньо. Транзитивних залежностей немає.

Перевірка НФБК: усі детермінанти є надключами (`order_number`, `supplier_id` у `SUPPLIER`, `sku_code`, `location_code`, складений ключ `ORDER_ITEM`). Отже, схема також у НФБК.

## 7. Результат і зв'язок з лабораторною 2

Після трьох кроків отримуємо таблиці, що відповідають схемі лабораторної 2:

| Таблиця з кроку 3 | Таблиця лабораторної 2 | Відповідність |
|---|---|---|
| `SUPPLIER` | `supplier` | ті самі атрибути (у лабораторній 2 додатково `contact_person`, `phone`, `email`, які тут не показані) |
| `PRODUCT` | `product` | ті самі атрибути |
| `LOCATION` | `warehouse_location` | те саме, крім `max_capacity` і `shelf_number`, які тут не показані |
| `ORDER` | `supply_order` | ті самі атрибути, у лабораторній 2 `batch_number` відсутній |
| `ORDER_ITEM` | `supply_item` | ті самі атрибути, у лабораторній 2 є `batch_number` |

Різниця: у лабораторній 2 `batch_number` стоїть у `supply_item`, а з кроку 2 випливає, що він визначається `order_number`. Це та сама часткова залежність 2НФ, тільки для `batch_number`. Тому фінальна схема переносить `batch_number` у `ORDER` (`supply_order`).

Зміни в таблицях (`ALTER TABLE`):
```sql
ALTER TABLE supply_order ADD COLUMN batch_number VARCHAR(50);
UPDATE supply_order o SET batch_number = (
    SELECT DISTINCT i.batch_number FROM supply_item i WHERE i.order_id = o.order_id);
ALTER TABLE supply_order ALTER COLUMN batch_number SET NOT NULL;
ALTER TABLE supply_item DROP COLUMN batch_number;
```

Перед запуском перевіряється, що `SELECT order_id FROM supply_item GROUP BY order_id HAVING COUNT(DISTINCT batch_number) > 1` повертає 0 рядків. Уся міграція виконується в одній транзакції (`BEGIN` / `COMMIT`), скрипт `docs/lab5/migration_batch_to_order.sql`.

Фінальна схема змінених таблиць:

```sql
CREATE TABLE supply_order (
    order_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_number VARCHAR(50)   NOT NULL UNIQUE,
    supplier_id  INTEGER       NOT NULL REFERENCES supplier (supplier_id),
    supply_date  TIMESTAMP     NOT NULL DEFAULT now(),
    total_cost   NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (total_cost >= 0),
    status       order_status  NOT NULL DEFAULT 'draft',
    batch_number VARCHAR(50)   NOT NULL
);

CREATE TABLE supply_item (
    order_id     INTEGER       NOT NULL REFERENCES supply_order (order_id),
    product_id   INTEGER       NOT NULL REFERENCES product (product_id),
    location_id  INTEGER       NOT NULL REFERENCES warehouse_location (location_id),
    quantity     INTEGER       NOT NULL CHECK (quantity > 0),
    unit_price   NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    expiry_date  DATE,
    PRIMARY KEY (order_id, product_id)
);
```

`total_cost` залишається в `ORDER` як похідна колонка. Це денормалізація, а не порушення нормальної форми (ФЗ між неключовими атрибутами немає). Коректність перевіряє блок 4 `lab5_normalization.sql`.

## 8. Перевірка виконання

- [x] Описано ненормалізовану форму і порушення 1НФ.
- [x] Визначено ФЗ для ненормалізованої таблиці.
- [x] Крок 1: 1НФ (винесено позиції в рядки).
- [x] Крок 2: 2НФ (винесено часткові залежності від `order_number` і `sku_code`).
- [x] Крок 3: 3НФ (винесено транзитивні залежності через `supplier_id` і `location_code`).
- [x] Перевірено НФБК для фінальних таблиць.
- [x] Наведено `ALTER TABLE` і фінальні `CREATE TABLE`.
- [ ] Скрипти виконано в PostgreSQL (psql у системі не знайдено; перевірити в pgAdmin).
- [ ] Діаграму `diagram.mmd` оновлено і експортовано в PNG/PDF.

## 9. Висновки

- Ненормалізована накладна має порушення 1НФ (повторювані групи позицій), 2НФ (часткові залежності від `order_number` і `sku_code`) і 3НФ (транзитивні залежності через `supplier_id` і `location_code`).
- Після трьох кроків отримано таблиці, що відповідають схемі лабораторної 2. Фінальна схема в 3НФ і НФБК.
- Єдина зміна відносно лабораторної 2: `batch_number` переноситься з `supply_item` у `supply_order`. Це залежить від правила «одна партія на накладну», яке треба підтвердити. Якщо правило інше, перенесення не потрібне, і ця зміна не застосовується.
