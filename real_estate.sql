/* Проект первого модуля: анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
 * 
 * Автор: Булатова Юлия Ивановна
 * Дата: 09.12.2024
*/

-- Фильтрация данных от аномальных значений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH l AS(
SELECT percentile_disc(0.99) WITHIN GROUP(ORDER BY total_area) AS l_area,
percentile_disc(0.99) WITHIN GROUP(ORDER BY rooms) AS l_rooms,
percentile_disc(0.99) WITHIN GROUP(ORDER BY balcony) AS l_balcony,
percentile_disc(0.99) WITHIN GROUP(ORDER BY ceiling_height) AS l_ceiling_height,
percentile_disc(0.01) WITHIN GROUP(ORDER BY ceiling_height) AS down_ceiling_height
FROM real_estate.flats
),
filtred_flats AS (
SELECT id 
FROM real_estate.flats
WHERE total_area<(SELECT l_area FROM l)
AND rooms<(SELECT l_rooms FROM l)
AND balcony<(SELECT l_balcony FROM l)
AND ceiling_height<(SELECT l_ceiling_height FROM l)
AND ceiling_height>(SELECT down_ceiling_height FROM l)
)
SELECT id 
FROM filtred_flats;

-- Задача 1: Время активности объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. Какие сегменты рынка недвижимости Санкт-Петербурга и городов Ленинградской области 
--    имеют наиболее короткие или длинные сроки активности объявлений?
-- 2. Какие характеристики недвижимости, включая площадь недвижимости, среднюю стоимость квадратного метра, 
--    количество комнат и балконов и другие параметры, влияют на время активности объявлений? 
--    Как эти зависимости варьируют между регионами?
-- 3. Есть ли различия между недвижимостью Санкт-Петербурга и Ленинградской области по полученным результатам?
WITH l AS(
SELECT percentile_disc(0.99) WITHIN GROUP(ORDER BY total_area) AS l_area,
percentile_disc(0.99) WITHIN GROUP(ORDER BY rooms) AS l_rooms,
percentile_disc(0.99) WITHIN GROUP(ORDER BY balcony) AS l_balcony,
percentile_disc(0.99) WITHIN GROUP(ORDER BY ceiling_height) AS l_ceiling_height,
percentile_disc(0.01) WITHIN GROUP(ORDER BY ceiling_height) AS down_ceiling_height
FROM real_estate.flats
),
filtred_flats AS (
SELECT id 
FROM real_estate.flats
WHERE total_area<(SELECT l_area FROM l)
AND rooms<(SELECT l_rooms FROM l)
AND balcony<(SELECT l_balcony FROM l)
AND ceiling_height<(SELECT l_ceiling_height FROM l)
AND ceiling_height>(SELECT down_ceiling_height FROM l)
),
saint_petersburg AS(
SELECT city,
f.id,
days_exposition,
CASE WHEN days_exposition<=30 
THEN 'до месяца'
WHEN days_exposition<=90 
THEN 'до трех месяцев'
WHEN days_exposition<=180
THEN 'до шести месяцев'
WHEN days_exposition>180
THEN 'больше шести месяцев'
END AS segment,
total_area,
last_price/total_area AS price_per_metr,
rooms,
balcony,
floor 
FROM filtred_flats AS f
LEFT JOIN real_estate.flats AS fl ON f.id=fl.id
LEFT JOIN real_estate.city AS C USING(city_id)
LEFT JOIN real_estate.advertisement AS a ON f.id=a.id
WHERE city='Санкт-Петербург' AND days_exposition IS NOT NULL
),
len_obl AS (
SELECT CASE WHEN city<> 'Санкт-Петербург'
THEN 'Ленинградская область'
END AS city,
f.id,
days_exposition,
CASE WHEN days_exposition<=30 
THEN 'до месяца'
WHEN days_exposition<=90 
THEN 'до трех месяцев'
WHEN days_exposition<=180 
THEN 'до шести месяцев'
WHEN days_exposition>180
THEN 'больше шести месяцев'
END AS segment,
total_area,
last_price/total_area AS price_per_metr,
rooms,
balcony,
floor
FROM filtred_flats AS f
LEFT JOIN real_estate.flats AS fl ON f.id=fl.id
LEFT JOIN real_estate.city AS C USING(city_id)
LEFT JOIN real_estate.advertisement AS a ON f.id=a.id
LEFT JOIN real_estate.TYPE AS t ON fl.type_id=t.type_id
WHERE city<>'Санкт-Петербург' AND days_exposition IS NOT NULL AND TYPE='город'
)
(SELECT segment,
city,
COUNT(id) AS total_ad,
ROUND(COUNT(id)::NUMERIC/(SELECT COUNT(id) FROM saint_petersburg),2)  AS part_of_ad,
ROUND(AVG(days_exposition)::NUMERIC,2) AS avg_days_exposition,
ROUND(AVG(price_per_metr)::NUMERIC,2) AS avg_price_per_metr,
ROUND(AVG(total_area)::NUMERIC,2) AS avg_total_area,
ROUND(AVG(rooms)::NUMERIC,2) AS avg_rooms,
ROUND(AVG(balcony)::NUMERIC,2) AS avg_balcony,
ROUND(AVG(floor)::NUMERIC,2) AS avg_floor
FROM saint_petersburg
GROUP BY segment, city
ORDER BY avg_days_exposition)
--объединяем с Ленинградской областью в одну таблицу
UNION ALL
(SELECT segment,
city,
COUNT(id) AS total_ad,
ROUND(COUNT(id)::numeric/(SELECT COUNT(id) FROM len_obl),2) AS part_of_ad,
ROUND(AVG(days_exposition)::NUMERIC,2) AS avg_days_exposition,
ROUND(AVG(price_per_metr)::NUMERIC,2) AS avg_price_per_metr,
ROUND(AVG(total_area)::NUMERIC,2) AS avg_total_area,
ROUND(AVG(rooms)::NUMERIC,2) AS avg_rooms,
ROUND(AVG(balcony)::NUMERIC,2) AS avg_balcony,
ROUND(AVG(floor)::NUMERIC,2) AS avg_floor
FROM len_obl
GROUP BY segment, city
ORDER BY avg_days_exposition);

-- Задача 2: Сезонность объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. В какие месяцы наблюдается наибольшая активность в публикации объявлений о продаже недвижимости? 
--    А в какие — по снятию? Это показывает динамику активности покупателей.
-- 2. Совпадают ли периоды активной публикации объявлений и периоды, 
--    когда происходит повышенная продажа недвижимости (по месяцам снятия объявлений)?
-- 3. Как сезонные колебания влияют на среднюю стоимость квадратного метра и среднюю площадь квартир? 
--    Что можно сказать о зависимости этих параметров от месяца?

WITH l AS(
SELECT percentile_disc(0.99) WITHIN GROUP(ORDER BY total_area) AS l_area,
percentile_disc(0.99) WITHIN GROUP(ORDER BY rooms) AS l_rooms,
percentile_disc(0.99) WITHIN GROUP(ORDER BY balcony) AS l_balcony,
percentile_disc(0.99) WITHIN GROUP(ORDER BY ceiling_height) AS l_ceiling_height,
percentile_disc(0.01) WITHIN GROUP(ORDER BY ceiling_height) AS down_ceiling_height
FROM real_estate.flats
),
filtred_flats AS (
SELECT id 
FROM real_estate.flats
WHERE total_area<(SELECT l_area FROM l)
AND rooms<(SELECT l_rooms FROM l)
AND balcony<(SELECT l_balcony FROM l)
AND ceiling_height<(SELECT l_ceiling_height FROM l)
AND ceiling_height>(SELECT down_ceiling_height FROM l)
),
--добавляю к объявлениям дату снятия с публикации
dates AS( 
SELECT id,
last_price/total_area AS price_for_metr,
total_area,
to_char(first_day_exposition,'Month') AS start_date,
to_char(first_day_exposition+days_exposition::integer,'Month') AS end_date
FROM real_estate.advertisement AS a 
JOIN filtred_flats AS fl USING(id)
LEFT JOIN real_estate.flats AS f USING(id)
LEFT JOIN real_estate.TYPE AS t ON t.type_id=f.TYPE_id
WHERE days_exposition IS NOT NULL AND TYPE='город' AND DATE_TRUNC('year', first_day_exposition)<>'2014-01-01'
AND DATE_TRUNC('year', first_day_exposition)<>'2019-01-01'
),
--считаю необходимые показатели для месяцев начала публикаций
s_d AS(
SELECT start_date,
AVG(price_for_metr) AS price_for_metr_s,
AVG(total_area) AS a_total_area_s,
COUNT(id) AS p_started
FROM dates
GROUP BY start_date
),
--показатели для месяца снятия с публикаций 
e_d AS (
SELECT end_date,
AVG(price_for_metr) AS price_for_metr_e,
AVG(total_area) AS a_total_area_e,
COUNT(id) AS p_ended
FROM dates 
GROUP BY end_date
)
--пишу итоговый запрос, вычисляя необходимые данные и ранжируя месяцы исходя из количества открытых/закрытых публикаций
SELECT DENSE_RANK() OVER(ORDER BY p_started DESC) AS rank_opened_ads,
DENSE_RANK() OVER(ORDER BY p_ended DESC) AS rank_closed_ads,
start_date AS month,
p_started AS opened_ads,
ROUND(p_started/(SELECT SUM(p_started) FROM s_d),2) AS part_from_total_opened,
p_ended AS closed_ads,
ROUND(p_ended/(SELECT SUM(p_ended) FROM e_d),2) AS part_from_total_closed,
ROUND((price_for_metr_s+price_for_metr_e)::numeric/2,0) AS avg_price_for_metr,
ROUND((a_total_area_s+a_total_area_e)::numeric/2,0) AS avg_total_area
FROM s_d AS sd
JOIN e_d AS ed ON sd.start_date=ed.end_date
ORDER BY avg_price_for_metr;

-- Задача 3: Анализ рынка недвижимости Ленобласти
-- Результат запроса должен ответить на такие вопросы:
-- 1. В каких населённые пунктах Ленинградской области наиболее активно публикуют объявления о продаже недвижимости?
-- 2. В каких населённых пунктах Ленинградской области — самая высокая доля снятых с публикации объявлений? 
--    Это может указывать на высокую долю продажи недвижимости.
-- 3. Какова средняя стоимость одного квадратного метра и средняя площадь продаваемых квартир в различных населённых пунктах? 
--    Есть ли вариация значений по этим метрикам?
-- 4. Среди выделенных населённых пунктов какие пункты выделяются по продолжительности публикации объявлений? 
--    То есть где недвижимость продаётся быстрее, а где — медленнее.
WITH l AS(
SELECT percentile_disc(0.99) WITHIN GROUP(ORDER BY total_area) AS l_area,
percentile_disc(0.99) WITHIN GROUP(ORDER BY rooms) AS l_rooms,
percentile_disc(0.99) WITHIN GROUP(ORDER BY balcony) AS l_balcony,
percentile_disc(0.99) WITHIN GROUP(ORDER BY ceiling_height) AS l_ceiling_height,
percentile_disc(0.01) WITHIN GROUP(ORDER BY ceiling_height) AS down_ceiling_height
FROM real_estate.flats
),
filtred_flats AS (
SELECT id 
FROM real_estate.flats
WHERE total_area<(SELECT l_area FROM l)
AND rooms<(SELECT l_rooms FROM l)
AND balcony<(SELECT l_balcony FROM l)
AND ceiling_height<(SELECT l_ceiling_height FROM l)
AND ceiling_height>(SELECT down_ceiling_height FROM l)
),
sold AS (
SELECT city,
COUNT(id) AS solded,
ROUND(AVG(days_exposition)::numeric,0) AS avg_days_exposition
FROM filtred_flats AS fl 
JOIN real_estate.advertisement AS a USING(id)
JOIN real_estate.flats AS f USING(id)
JOIN real_estate.city AS c USING(city_id)
WHERE days_exposition IS NOT NULL
GROUP BY city
),
all_ad AS (
SELECT city,
COUNT(fl.id) AS total_ad,
ROUND(AVG(last_price/total_area)::NUMERIC,0) AS avg_price_for_metr,
ROUND(AVG(total_area)::NUMERIC,0) AS avg_total_area
FROM filtred_flats AS fl 
JOIN real_estate.flats AS f USING(id)
JOIN real_estate.city AS c USING(city_id)
JOIN real_estate.advertisement AS a USING(id)
GROUP BY city
),
for_final AS(
SELECT city,
total_ad,
COALESCE(solded,0) AS solded,
COALESCE(ROUND(solded/total_ad::NUMERIC,2),0) AS part_of_solded,
avg_days_exposition,-- не заменяю NULL-значения на 0, чтобы не вводить в заблуждение относительно скорости продажи 
avg_price_for_metr, 
avg_total_area
FROM all_ad AS a 
LEFT JOIN sold AS s USING(city)
)
SELECT *
FROM for_final
WHERE total_ad>50 AND city<>'Санкт-Петербург'
ORDER BY part_of_solded DESC;