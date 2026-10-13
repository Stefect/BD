# Специфікація бази даних WMS (Warehouse Management System)

Джерело вимог: `README.md` (розділ "Бізнес-правила"). Схема: `docs/adr/schema.sql`. Тести: `docs/adr/tests.sql`. Діаграма: `docs/adr/diagram.mmd`.

## 1. Вимоги та трасованість

| ID | Вимога | Реалізація | Перевірка |
|---|---|---|---|
| R-01 | Довідник товарів: унікальний артикул, одиниці виміру, мінімальний залишок >= 0 | `product`; CHECK на `sku_code`, `unit`, `min_stock_level` | T14, T15, T17 |
| R-02 | Постачальники: унікальний email без урахування регістру, формат телефону | `supplier`; індекс `uq_supplier_email_ci`; CHECK на `phone`, `email` | T12, T13 |
| R-03 | Адресна структура складу: унікальний код, пара (zone, shelf_number) унікальна, місткість комірки не перевищується | `warehouse_location`; `fn_adjust_stock` (перевірка місткості) | T06 |
| R-04 | Накладна: створюється як draft; дозволені переходи: з draft у received і з draft у cancelled; отриману без позицій не можна отримати; змінювати і видаляти можна лише чернетку | `supply_order`; тригери `trg_order_insert`, `trg_order_update`, `trg_order_delete` | T07, T08, T09, T10, T11 |
| R-05 | Позиції накладної: товар, кількість, ціна, партія, термін придатності; сума накладної дорівнює сумі позицій | `supply_item` (PK складений); тригери `trg_item_guard`, `trg_item_total` | T16, T18 |
| R-06 | Оприбуткування: при переході в received залишки збільшуються в комірках приймання | тригер `trg_order_receive`, функція `fn_order_receive` | T19, перевірка надходжень у schema.sql |
| R-07 | Залишки товару по комірках не можуть бути від'ємними | `inventory_stock`; CHECK і `fn_adjust_stock` | T01 |
| R-08 | Переміщення між комірками: від різних комірок, залишок достатній | `inventory_movement`; `trg_movement_apply`; CHECK `chk_different_locations` | T01, T02 |
| R-09 | Списання: без комірки-отримувача, зменшує залишок | `movement_type = 'write_off'`; CHECK `chk_movement_type_target` | T03, перевірка списань у schema.sql |
| R-10 | Аудит: кожна операція має автора, час і причину; журнал незмінний | `created_by`, `movement_date`, `reason`; `trg_movement_immutable` | T04, T05 |
| R-11 | Контроль мінімальних залишків: показати товари, нижче мінімуму | представлення `v_low_stock` | `SELECT * FROM v_low_stock` у schema.sql |
| R-12 | Звіти по залишках: загальний залишок товару і завантаженість комірок | представлення `v_stock_by_product`, `v_location_load` | SELECT у schema.sql |
| R-13 | Цілісність посилань: використовувані записи не видаляються, накладна каскадно видаляє свої позиції (лише чернетка) | FK з `ON DELETE RESTRICT` / `CASCADE` | T11, T17 |

Користувацьких сценаріїв (use case) у проєкті немає. Вимоги зведено з `README.md` до переліку R-01..R-13 вище.

## 2. Сутності та атрибути

- **Постачальник (supplier)**: `supplier_id` (PK, IDENTITY), `company_name`, `contact_person`, `phone` (NOT NULL, формат `+` і 10-15 цифр), `email` (NOT NULL, унікальний без урахування регістру), `address`.
- **Товар (product)**: `product_id` (PK, IDENTITY), `sku_code` (NOT NULL, UNIQUE, лише A-Z, 0-9, дефіс), `name`, `description` (необов'язковий), `unit` (NOT NULL, DEFAULT 'piece', CHECK: piece, kg, liter, box, pallet), `min_stock_level` (NOT NULL, DEFAULT 0, CHECK >= 0).
- **Комірка складу (warehouse_location)**: `location_id` (PK, IDENTITY), `location_code` (NOT NULL, UNIQUE, формат LOC-X-n), `zone`, `shelf_number` (UNIQUE разом), `max_capacity` (NOT NULL, CHECK > 0).
- **Накладна (supply_order)**: `order_id` (PK, IDENTITY), `order_number` (NOT NULL, UNIQUE), `supplier_id` (NOT NULL, FK, RESTRICT), `supply_date` (TIMESTAMPTZ, DEFAULT now()), `total_cost` (NOT NULL, DEFAULT 0, CHECK >= 0, оновлюється тригером), `status` (NOT NULL, DEFAULT 'draft', CHECK: draft, received, cancelled), `created_at`, `created_by`.
- **Позиція накладної (supply_item)**: `order_id` (PK частина, FK, CASCADE), `product_id` (PK частина, FK, RESTRICT), `location_id` (NOT NULL, FK, RESTRICT, комірка приймання), `quantity` (NOT NULL, CHECK > 0), `unit_price` (NOT NULL, CHECK >= 0), `batch_number` (NOT NULL, партія постачання), `expiry_date` (необов'язкова).
- **Залишок (inventory_stock)**: `product_id` і `location_id` (складений PK), `quantity` (NOT NULL, CHECK >= 0). Змінюють лише тригери.
- **Переміщення (inventory_movement)**: `movement_id` (PK, IDENTITY), `movement_type` (NOT NULL, CHECK: transfer, write_off), `product_id` (FK, RESTRICT), `from_location_id` (NOT NULL, FK, RESTRICT), `to_location_id` (FK, RESTRICT; NOT NULL для transfer, NULL для write_off), `quantity` (NOT NULL, CHECK > 0), `reason` (необов'язкова причина), `movement_date` (TIMESTAMPTZ, DEFAULT now()), `created_by` (DEFAULT current_user).

## 3. Ключі

- Сутності supplier, product, warehouse_location, supply_order, inventory_movement мають сурогатний PK `INT GENERATED ALWAYS AS IDENTITY` (ADR 0001).
- Таблиці сполучення supply_item і inventory_stock мають складений PK з двох FK (ADR 0001, ADR 0002).

## 4. Правила накладних (статусна модель)

Діаграма станів:
- стан draft (чернетка) має два дозволені переходи;
- перехід draft у received (оприбуткування, залишки збільшуються), фінальний стан received;
- перехід draft у cancelled (залишки не змінюються), фінальний стан cancelled.

- Нова накладна створюється лише в статусі `draft`.
- У статусі `draft` можна змінювати позиції, додавати і видаляти накладну.
- Перехід у `received` вимагає хоча б однієї позиції. Тригер збільшує залишок кожної позиції в її `location_id`.
- `received` і `cancelled` є фінальними: статус, позиції, сума, постачальник і номер не змінюються.
- `total_cost` завжди дорівнює сумі `quantity * unit_price` позицій (тригер після будь-якої зміни позицій).

## 5. Правила переміщень

- `transfer`: залишок у `from_location` зменшується, у `to_location` збільшується. Комірки різні.
- `write_off`: залишок у `from_location` зменшується. `to_location` порожній.
- Якщо залишок стане від'ємним, операція відхиляється. Якщо місткість комірки буде перевищена, операція відхиляється.
- Записи журналу не можна змінювати або видаляти. Виправлення робиться новим переміщенням зі зворотним напрямом.

## 6. Граничні випадки та обробка помилок

| Випадок | Поведінка |
|---|---|
| Email відрізняється лише регістром | Відхиляється (індекс без урахування регістру) |
| Телефон без `+` або з літерами | Відхиляється (CHECK) |
| Артикул у нижньому регістрі | Відхиляється (CHECK) |
| Переміщення понад залишок | Відхиляється, повідомлення містить товар, комірку і залишок |
| Переміщення в ту саму комірку | Відхиляється (CHECK) |
| Списання з коміркою-отримувачем | Відхиляється (CHECK) |
| Переповнення комірки | Відхиляється, повідомлення містить зайнятість і місткість |
| Зміна позицій отриманої або скасованої накладної | Відхиляється |
| Отримання накладної без позицій | Відхиляється |
| Повернення скасованої накладної в чернетку | Відхиляється |
| Видалення отриманої накладної | Відхиляється |
| Видалення товару, який є в накладних або залишках | Відхиляється (RESTRICT) |
| Зміна або видалення запису переміщення | Відхиляється (журнал незмінний) |
| Нульова або від'ємна кількість | Відхиляється (CHECK) |

Тексти помилок бази виводяться українською мовою. Застосунок має показувати їх користувачу без змін або перекласти за кодом помилки.

## 7. Обмеження (свідомо поза межами)

Ці пункти не реалізовано. Їх треба або підтвердити як поза межами курсу, або додати окремо.

1. **Залишки ведуться без розбивки за партією.** `batch_number` записується в позицію накладної, але залишок товару в комірці агрегований. Облік FEFO (витрата найближчого терміну) не реалізовано.
2. **Немає користувачів і ролей.** `created_by` приймає ім'я користувача БД (`current_user`). Автентифікація й права доступу не моделюються.
3. **Немає інвентаризації.** Не описано процес звірки фізичного залишку з обліковим.
4. **Одиниці виміру не конвертуються.** `unit` є довідковим атрибутом товару, переміщення і накладні використовують кількість у цій одиниці.
5. **Місткість комірки у штуках** (абстрактні одиниці, `max_capacity`), без розмірів і ваги.
6. **Валюта одна** (ціни без валюти).
7. **Часові пояси** зберігаються як TIMESTAMPTZ, показ у локальному поясі залежить від клієнта.

## 8. Процеси (як дані записуються і читаються)

- **Створення накладної:** INSERT у `supply_order` (статус draft), потім INSERT позицій у `supply_item`. Сума рахується тригером.
- **Оприбуткування:** `UPDATE supply_order SET status = 'received'`. Залишки збільшуються тригером.
- **Скасування:** `UPDATE supply_order SET status = 'cancelled'` (лише з draft).
- **Переміщення:** INSERT у `inventory_movement` (тип transfer). Залишки оновлюються тригером.
- **Списання:** INSERT у `inventory_movement` (тип write_off).
- **Залишки по товару:** `SELECT * FROM v_stock_by_product`.
- **Товари нижче мінімуму:** `SELECT * FROM v_low_stock`.
- **Завантаженість комірок:** `SELECT * FROM v_location_load`.
- **Історія переміщень:** `SELECT * FROM inventory_movement ORDER BY movement_date`.
- **Накладні за статусом:** `SELECT * FROM supply_order WHERE status = 'draft'`.

## 9. Припущення

1. Залишок у комірці є операційним станом. Він змінюється лише тригерами з накладних і переміщень, а не прямими UPDATE (прямий UPDATE можливий для адміністратора, але порушує аудит; для продуктивної системи варто обмежити права).
2. Ціна в позиції фіксується на момент надходження.
3. Видалення накладної, позиції якої вже оприбутковані, неможливе, тому історія залишків не втрачається.
