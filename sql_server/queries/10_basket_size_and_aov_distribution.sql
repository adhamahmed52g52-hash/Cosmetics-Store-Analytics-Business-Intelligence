-- *****************************************************************************
-- 10_basket_size_and_aov_distribution.sql
-- تحليل حجم سلة الشراء ومكوناتها وتوزيع قيم الفواتير إحصائياً (AOV & Basket Size)
-- *****************************************************************************

use cosmetics_store;
go

-- 1) مقارنة إحصائية بين المتوسط الحسابي والوسيط والمئينات لقيم الفواتير ومكونات السلة
--------------------------------------------------------------------------------
with OrderPercentileCalculations as ( --> CTE بنحسب فيه المئينات الإحصائية لقيم الفواتير
    select 
        final_total,
        total_qty,
        percentile_cont(0.50) within group (order by final_total) over () as [MedianOrderValue], --> الوسيط الحسابي Median لقيمة الفواتير
        percentile_cont(0.25) within group (order by final_total) over () as [P25_OrderValue], --> المئين 25 (25% من الفواتير أقل من هذا الرقم)
        percentile_cont(0.75) within group (order by final_total) over () as [P75_OrderValue], --> المئين 75
        percentile_cont(0.90) within group (order by final_total) over () as [P90_OrderValue] --> المئين 90
    from dbo.FactSalesInvoice
    where is_retail_sale = 1 --> مبيعات التجزئة فقط
)
select distinct --> distinct لمنع تكرار نفس القيم الإحصائية مع كل صف
    (select count(*) from dbo.FactSalesInvoice where is_retail_sale = 1) as [TotalRetailInvoicesCount], --> إجمالي عدد فواتير التجزئة
    (select round(avg(final_total), 2) from dbo.FactSalesInvoice where is_retail_sale = 1) as [MeanOrderValue], --> المتوسط الحسابي لقيمة الفاتورة
    round(MedianOrderValue, 2) as [MedianOrderValue], --> الوسيط الحسابي
    round(P25_OrderValue, 2) as [Percentile25th], --> الربع الأول Q1
    round(P75_OrderValue, 2) as [Percentile75th], --> الربع الثالث Q3
    round(P90_OrderValue, 2) as [Percentile90th], --> المئين 90 لأعلى الفواتير قيمة
    (select round(avg(total_qty), 2) from dbo.FactSalesInvoice where is_retail_sale = 1) as [AverageItemsPerBasket] --> متوسط عدد القطع في سلة الشراء
from OrderPercentileCalculations;
go

-- 2) توزيع فواتير المبيعات على شرائح الإنفاق المختلفة (Spend Brackets)
--------------------------------------------------------------------------------
select 
    case 
        when final_total < 50 then 'Under 50 EGP' --> فواتير صغيرة جداً
        when final_total between 50 and 99.99 then '50 - 99 EGP' --> فواتير متوسطة صغيرة
        when final_total between 100 and 199.99 then '100 - 199 EGP' --> الشريحة الأساسية لمبيعات المحل
        when final_total between 200 and 499.99 then '200 - 499 EGP' --> فواتير مرتفعة القيمة
        when final_total between 500 and 999.99 then '500 - 999 EGP' --> فواتير عالية القيمة
        else '1,000+ EGP (High-Value VIP Baskets)' --> فواتير كبرى وسلات شراء مميزة
    end as [SpendBracket],
    count(invoice_no) as [OrdersCount], --> عدد الفواتير في الشريحة
    round(count(invoice_no) * 100.0 / (select count(*) from dbo.FactSalesInvoice where is_retail_sale = 1), 2) as [OrdersSharePct], --> نسبة الفواتير المئوية
    sum(final_total) as [TotalRevenue], --> إجمالي الإيراد المحقق من الشريحة
    round(sum(final_total) * 100.0 / (select sum(final_total) from dbo.FactSalesInvoice where is_retail_sale = 1), 2) as [RevenueSharePct] --> حصة الشريحة من إجمالي المبيعات
from dbo.FactSalesInvoice
where is_retail_sale = 1 --> مبيعات التجزئة فقط
group by 
    case 
        when final_total < 50 then 'Under 50 EGP'
        when final_total between 50 and 99.99 then '50 - 99 EGP'
        when final_total between 100 and 199.99 then '100 - 199 EGP'
        when final_total between 200 and 499.99 then '200 - 499 EGP'
        when final_total between 500 and 999.99 then '500 - 999 EGP'
        else '1,000+ EGP (High-Value VIP Baskets)'
    end
order by min(final_total) asc;
go
