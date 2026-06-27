#   Задания Модуля 2
---
## 2.1. SQL запросы

*Выведем ключевые метрики следующим запросом. Не забудем, что из результатов надо исключить заказы, которые были возвращены:*  
```sql
SELECT 
    ROUND(SUM(sf.sales), 2) as "Total Sales, USD", 
    ROUND(SUM(sf.profit), 2) as "Total Profit, USD", 
    ROUND(SUM(sf.profit)/SUM(sf.sales)*100, 0) as "Profit Ratio, %", 
    ROUND(SUM(sf.profit)/COUNT(DISTINCT sf.order_id), 2) as "Profit per Order, USD", 
    ROUND(SUM(sf.sales)/COUNT(DISTINCT sf.customer_id), 2) as "Sales per Customer, USD", 
    ROUND(AVG(d.discount_usd), 2) as "AVG DISCOUNT, USD", 
    ROUND(AVG(d.discount_perc), 0) as "AVG Discount, %"
FROM 
    sales_fact sf
LEFT JOIN (
    SELECT 
        order_id, 
        ROUND(SUM(discount*sales), 2) as discount_usd, 
        ROUND(SUM(discount*sales)/SUM(sales)*100, 0) as discount_perc
    FROM 
        sales_fact
    WHERE 
        discount > 0 AND discount IS NOT NULL
    GROUP BY 
        order_id
) as d ON sf.order_id = d.order_id
left join returns as r on sf.order_id = r.order_id
where r.returned is NULL  
```
**Результат:**

Total Sales, USD|Total Profit, USD|Profit Ratio, %|Profit per Order, USD|Sales per Customer, USD|AVG DISCOUNT, USD|AVG Discount, %|
---------------|-----------------|---------------|---------------------|-----------------------|-----------------|---------------
   2107767.21   |   260919.68   |   12   |   55.43   |   2664.69   |   160.36   |   27   |

***
*Сопоставим кол-во заказов с возвратами и без. Помним, что в исходной таблице номера заказов повторяются, поэтому считаем только уникальные зачения с помощью 'distinct':*
```sql
select count(distinct sf.order_id)-count(distinct r.order_id) as "NOT RETURNED", count(distinct r.order_id) as "RETURNED"
from sales_fact as sf
left join returns as r USING(order_id)
```
**Результат:**

NOT RETURNED|RETURNED
------------|--------
   4707   |   296   |

***
*Выведим Продажи и Прибыль по категориям. Отсортируем по убыванию Выручки:*

```sql
select category as "Category name", ROUND(sum(sales),2) as "Total sales, USD", ROUND(sum(profit),2) as "Total profit, USD"
from product p
left join sales_fact sf USING(product_id)
group by category
order by "Total sales, USD" DESC, "Total profit, USD" DESC
```
**Результат:**

Category name  |Total sales, USD|Total profit, USD|
---------------|----------------|-----------------
Technology     |   834554.27|   145007.66   |
Furniture      |   736879.70|   17259.35   |
Office Supplies|   716837.52|   121885.04   |

***
*Выведем продажи сегментов, упорядочим по месяцам и по убыванию продаж. Ограничим результат 6 линиями (для экономии):*
```sql
SELECT 
    c.month_name AS MONTH, 
    o.segment, 
    SUM(sf.sales) AS total_sales
FROM 
    "order" o
LEFT JOIN 
    sales_fact sf USING (order_id)
LEFT JOIN 
    calendar c ON EXTRACT(MONTH FROM o.order_date) = c.month_number
GROUP BY c.month_name, o.segment, c.month_number
order by c.month_number, total_sales desc;
```
**Результат:**

month   |segment    |total sales, USD|
--------|-----------|----------------
January |Consumer   |        49804.11|
January |Corporate  |        25118.04|
January |Home Office|        17693.20|
February|Consumer   |        33826.18|
February|Corporate  |        14575.07|
February|Home Office|        11350.01|

***

*С помощью оконных функций оставим только те сегменты, продажи которых были максимальны в каждый из месяцев:*

```sql
SELECT 
    MONTH,
    segment,
    "total sales, USD"
FROM 
(
SELECT 
        c.month_name AS MONTH,
        c.month_number,
        o.segment, 
        ROUND(SUM(sf.sales),2) AS "total sales, USD",
        RANK() OVER (PARTITION BY c.month_number ORDER BY SUM(sf.sales) DESC) AS sales_rank
    FROM 
        "order" o
    LEFT JOIN 
        sales_fact sf USING (order_id)
    LEFT JOIN 
        calendar c ON EXTRACT(MONTH FROM o.order_date) = c.month_number
    GROUP BY 
        c.month_name, o.segment, c.month_number
)
WHERE 
    sales_rank = 1
ORDER BY 
    month_number;
```

**Результат:**
month    |segment  |total sales, USD|
---------|---------|----------------
January  |Consumer |        49804.11|
February |Consumer |        33826.18|
March    |Consumer |        89174.71|
April    |Consumer |        54845.19|
May      |Consumer |        86932.71|
June     |Consumer |        82910.18|
July     |Consumer |        81769.77|
August   |Consumer |        82319.81|
September|Consumer |       185055.92|
October  |Corporate|        78291.76|
November |Consumer |       170243.54|
December |Consumer |       176453.76|

***
*Выведем аналогичный отчет по категориям товаров:*
```sql
select
	month, category,
	"total sales, USD"
from
(
	SELECT 
    c.month_name AS MONTH, c.month_number,
    p.category, 
    ROUND(SUM(sf.sales),2) AS "total sales, USD",
    rank() over (partition by c.month_number order by SUM(sf.sales) DESC) AS sales_rank
FROM 
    "order" o
LEFT JOIN 
    sales_fact sf USING (order_id)
LEFT JOIN 
    calendar c ON EXTRACT(MONTH FROM o.order_date) = c.month_number
left join product p on sf.product_id = p.product_id
GROUP BY c.month_name, p.category, c.month_number
having category is not null
)
WHERE 
    sales_rank = 1
ORDER BY 
    month_number;
```
**Результат:**

month    |category       |total sales, USD|
---------|---------------|----------------
January  |Furniture      |        31569.24|
February |Technology     |        23343.42|
March    |Technology     |        97851.57|
April    |Office Supplies|        49433.27|
May      |Technology     |        63642.16|
June     |Furniture      |        52999.46|
July     |Technology     |        54854.03|
August   |Office Supplies|        62134.16|
September|Furniture      |       106380.59|
October  |Technology     |        87031.95|
November |Technology     |       131134.84|
December |Furniture      |       121817.97|

***

## 2.2. Подключение к Базам Данных и SQL
1. _Устанавливаем PostgreSQL 17 и клиент DBeaver для подключения к БД._
2. *Создаем три таблицы и загружаем данные c помощью запросов в DBeaver*
     
**Cкрипты загрузки данных:**
  + [script_table_orders.sql](https://github.com/tangokarimoff/datalearn/blob/a4cb128b366045d952945a28b1c95f94241d3f13/de101/Module02/script_table_orders), 
  + [script_table_people.sql](https://github.com/tangokarimoff/datalearn/blob/a4cb128b366045d952945a28b1c95f94241d3f13/de101/Module02/script_table_people), 
  + [script_table_returns.sql](https://github.com/tangokarimoff/datalearn/blob/a4cb128b366045d952945a28b1c95f94241d3f13/de101/Module02/script_table_returns)
---
## 2.3. Модель данных.
Задача создать модель данных для файла с данными [superstore.xls](https://github.com/tangokarimoff/datalearn/blob/81f351348549390229ce3b9c37c159f4cd222584/de101/Module02/Superstore.xls).

_Для архитектуры БД выбрана схема "Звезда" по Инману. Создаем Dimensions таблицы, далее Sales_fact._

- **Концептуальная модель.**

_Определяем основные элементы. Можно сказать,составляем скорее диагрмму основных бизнес процессов   
(Что происходит между элементами?). Намечаем границы будущих таблиц._

![concept data model](https://github.com/tangokarimoff/datalearn/blob/3ac01fcb34dc3adc4ccf122f8b56e537f8a5978a/de101/Module02/img/ConceptModel.png)

- **Физическая модель.**

_Добавление синтаксиса. Можно сказать,что данный этап непосредственно является DDL._

![physical data model](https://github.com/tangokarimoff/datalearn/blob/3ac01fcb34dc3adc4ccf122f8b56e537f8a5978a/de101/Module02/img/PhysModel.png)

- **Generate SQL.**

_Генерируем SQL-запросы --> DDL. Выполняем в SQL клиенте._

- **Делаем ```insert into table```.**

_Заполняем Dimensions и Sales_fact._

[Create script_datamodeling_DDL.sql](https://github.com/tangokarimoff/datalearn/blob/3ac01fcb34dc3adc4ccf122f8b56e537f8a5978a/de101/Module02/script_datamodeling_DDL)- файл со скриптом.

---
## 2.4. Дашборд для конечного пользователя

В качестве BI решения воспользуемся 'Yandex DataLens'.

**Порядок действий:**
1. *Настраиваем подключение к БД.*
2. *Формируем Датасет. На уровне датасета добавляем аггрегации, которые будут использоваться в нескольких чартах (чтобы не создавать заново).*
3. *На основе датасета строим чарты и собираем дашборд. На дашборд добавляем необходимые селекторы для фильтрации данных (например, по дате заказа).*
4. *Группируем чарты и наводим порядок, чтобы все хорошо читалось.*

**Результат**
![](https://github.com/tangokarimoff/datalearn/blob/main/de101/Module02/img/DL_Dashboard.png)


