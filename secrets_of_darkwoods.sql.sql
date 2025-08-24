/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
 * 
 * Автор: Булатова Юлия Ивановна
 * Дата: 16.11.2024
*/

-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:
SELECT COUNT(DISTINCT id) AS total_users,
SUM(payer) AS paying_users,
SUM(payer)/COUNT(DISTINCT id)::float AS part_paying_users
FROM fantasy.users;

-- 1.2. Доля платящих пользователей в разрезе расы персонажа:
SELECT race_id,
SUM(payer) AS paying_users,
COUNT(DISTINCT id) AS total_users,
ROUND(SUM(payer)/COUNT(DISTINCT id)::numeric,4) AS part_paying_users
FROM fantasy.users
GROUP BY race_id;

-- Задача 2. Исследование внутриигровых покупок
-- 2.1. Статистические показатели по полю amount:
SELECT COUNT(amount) AS total_purchases,
SUM(amount) AS total_revenue,
MIN(amount) AS min_revenue,
MAX(amount) AS max_revenue,
ROUND(AVG(amount)::numeric,2) AS avg_revenue,
percentile_disc(0.5) WITHIN GROUP(ORDER BY amount) AS mediana,
ROUND(STDDEV(amount)::NUMERIC,2) AS standart_otkl
FROM fantasy.events 

-- 2.2: Аномальные нулевые покупки:
SELECT COUNT(amount) AS zero_purchases,
ROUND(COUNT(amount)::numeric/(SELECT COUNT(amount) FROM fantasy.events),4) AS zero_purchases_from_total
FROM fantasy.events 
WHERE amount=0;

-- 2.3: Сравнительный анализ активности платящих и неплатящих игроков:
SELECT CASE WHEN payer=1
THEN 'paying'
WHEN payer=0
THEN 'non-paying'
END AS segment,
COUNT(DISTINCT u.id) AS users_number,
ROUND(COUNT(transaction_id)/COUNT(DISTINCT u.id)::numeric,2) AS avg_purchases,
ROUND(SUM(amount)::numeric/COUNT(DISTINCT u.id), 2) AS avg_amount
FROM fantasy.events AS e
JOIN fantasy.users AS u USING(id)
WHERE amount<>0
GROUP BY segment;

-- 2.4: Популярные эпические предметы:
SELECT game_items,
COUNT(transaction_id) AS item_purchases,
COUNT(transaction_id)::float/(SELECT COUNT(transaction_id) FROM fantasy.events) AS purchases_from_total,
COUNT(DISTINCT id) AS distinct_users,
COUNT(DISTINCT id)::float/(SELECT COUNT(DISTINCT id) FROM fantasy.events) AS users_from_total
FROM fantasy.items AS i
LEFT JOIN fantasy.events AS e USING(item_code)
WHERE amount<>0
GROUP BY game_items
ORDER BY item_purchases DESC;

-- Часть 2. Решение ad hoc-задач
-- Задача 1. Зависимость активности игроков от расы персонажа:
--считаю количество игроков в разрезе рас
WITH total AS(
SELECT race_id,
COUNT(id) AS total_users
FROM fantasy.users 
GROUP BY race_id
),
--считаю количество игроков, которые совершают внутриигровые покупки
buyers AS (
SELECT u.race_id,
COUNT(DISTINCT e.id) AS buyer_number
FROM fantasy.users AS u
LEFT JOIN fantasy.events AS e USING(id)
GROUP BY u.race_id),
--считаю в разрезе расы количество платящих игроков, совершивших покупки
paying AS(
SELECT race_id,
COUNT(DISTINCT e.id) AS paying_users
FROM fantasy.users AS u
JOIN fantasy.events AS e USING(id)
WHERE payer=1
GROUP BY race_id),
--считаю статистические показатели для каждого игрока
stat AS (
SELECT race_id,
id,
SUM(amount) AS total_amount
FROM fantasy.users AS u 
JOIN fantasy.events AS e USING(id)
GROUP BY race_id, id),
--считаю среднее число покупок на расу 
avg AS(
SELECT race_id,
COUNT(transaction_id)/COUNT(DISTINCT id) AS avg_purchases
FROM fantasy.events AS e 
JOIN fantasy.users AS u USING(id)
GROUP BY race_id
),
--расчитываю средние показатели в разрезе расы
sr AS (
SELECT race_id,
avg_purchases AS avg_purchases_number_per_user,
ROUND(AVG(total_amount)::NUMERIC,4)/avg_purchases AS avg_amount_per_user,
ROUND(AVG(total_amount)::NUMERIC,4) AS avg_total_amount_per_user
FROM stat AS s 
JOIN avg AS a USING(race_id)
GROUP BY race_id, avg_purchases
)
--основной запрос, решающий задачу
SELECT t.race_id,
t.total_users,
b.buyer_number,
ROUND(b.buyer_number/t.total_users::NUMERIC,4) AS buyers_from_total,
ROUND(p.paying_users/b.buyer_number::NUMERIC,4) AS paying_from_buyers,
avg_purchases_number_per_user,
ROUND(avg_amount_per_user,2),
ROUND(avg_total_amount_per_user,2)
FROM total AS t 
JOIN buyers AS b ON t.race_id=b.race_id
JOIN sr ON sr.race_id=b.race_id
JOIN paying AS p ON p.race_id=sr.race_id;
-- Задача 2: Частота покупок
--считаю количество покупок на одного пользователи и расчитываю следующую дату транзакции, чтобы потом расчитать 
--интервалы между покупками
WITH users_inf AS(
SELECT id,
COUNT(transaction_id) OVER(PARTITION BY id) AS transaction_count,
date::date,
LEAD(date::date,1) OVER(PARTITION BY id ORDER BY date::date) AS lead_date
FROM fantasy.events
WHERE amount<>0
),
--рассчитываю среднее количество дней между покупками для каждого пользователя
avg AS (
SELECT DISTINCT id,
transaction_count,
AVG(lead_date - date) OVER(PARTITION BY id) AS avg_interval_per_user
FROM users_inf 
WHERE lead_date IS NOT NULL
AND transaction_count>25
),
--разделяю пользователей на три равные группы по значению среднего интервала между покупками
rang AS (
SELECT id,
transaction_count,
avg_interval_per_user,
NTILE(3) OVER(ORDER BY avg_interval_per_user) AS rang
FROM avg
),
--категоризирую пользователей по рангам, присвоенным в предыдущем запросе
ranking AS (
SELECT id,
transaction_count,
avg_interval_per_user,
CASE WHEN rang=1
THEN 'высокая частота'
WHEN rang=2
THEN 'умеренная частота'
WHEN rang=3
THEN 'низкая частота'
END AS frequency
FROM rang
),
--рассчитываю число платящих пользователей в разрезе присвоенной категории
paying AS(
SELECT r.id,
r.transaction_count,
r.avg_interval_per_user,
frequency,
SUM(payer) OVER(PARTITION BY frequency) AS paying
FROM ranking AS r
JOIN fantasy.users AS u USING(id)
)
--основной запрос
SELECT DISTINCT frequency,
paying,
ROUND(paying/(COUNT(id) OVER(PARTITION BY frequency))::numeric,4) AS paying_users_part,
ROUND(AVG(transaction_count) OVER(PARTITION BY frequency),2) AS avg_transactions,
ROUND(AVG(avg_interval_per_user) OVER(PARTITION BY frequency),2) AS avg_interval
FROM paying
ORDER BY avg_interval;
