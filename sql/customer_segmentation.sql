-- Сегментация клиентов для персонализированных CRM-коммуникаций
-- Учебный проект курса «Аналитик данных», ООО «Карпов Курсы»
-- https://karpov.courses/
--
-- Дата среза: 31 марта 2024 года (включительно).
-- Используются таблицы customers, orders и customer_actions.
-- Исходная учебная база не публикуется.

-- Сначала отдельно агрегируем заказы по каждому клиенту, чтобы не умножать строки при соединении с событиями.
WITH orders_metrics AS (
    SELECT
        customer_id,
        COUNT(DISTINCT CASE
            WHEN order_status = 'Delivered'
                 AND order_delivered_customer_time < DATE '2024-04-01'
            THEN order_id
        END) AS orders_count,
        AVG(CASE
            WHEN order_status = 'Delivered'
                 AND order_delivered_customer_time < DATE '2024-04-01'
            THEN EXTRACT(EPOCH FROM (
                order_delivered_customer_time - order_created_time
            )) / 86400.0
        END) AS avg_delivery_days
    FROM orders
    GROUP BY customer_id
),

-- Отдельно считаем события покупки до конца даты среза.
actions_metrics AS (
    SELECT
        customer_id,
        COUNT(CASE
            WHEN event_type = 'Purchase'
                 AND event_timestamp < DATE '2024-04-01'
            THEN 1
        END) AS purchase_events_count
    FROM customer_actions
    GROUP BY customer_id
),

-- Объединяем показатели: одна строка на одного клиента.
customer_metrics AS (
    SELECT
        c.customer_id,
        c.customer_city,
        DATE(c.created_at) AS registration_date,
        DATE '2024-03-31' - DATE(c.created_at) AS days_since_registration,
        COALESCE(om.orders_count, 0) AS orders_count,
        COALESCE(am.purchase_events_count, 0) AS purchase_events_count,
        om.avg_delivery_days
    FROM customers AS c
    LEFT JOIN orders_metrics AS om
        ON c.customer_id = om.customer_id
    LEFT JOIN actions_metrics AS am
        ON c.customer_id = am.customer_id
    WHERE c.created_at < DATE '2024-04-01'
)

-- Назначаем сегмент для выбора типа маркетинговой коммуникации.
SELECT
    customer_id,
    customer_city,
    registration_date,
    days_since_registration,
    orders_count,
    purchase_events_count,
    avg_delivery_days,
    CASE
        WHEN orders_count >= 3 THEN 'Постоянный'
        WHEN orders_count IN (1, 2) THEN 'Разовый'
        WHEN orders_count = 0 AND days_since_registration > 30 THEN 'Неактивный'
        WHEN orders_count = 0 AND days_since_registration <= 30 THEN 'Новый'
    END AS segment
FROM customer_metrics
ORDER BY customer_id;
