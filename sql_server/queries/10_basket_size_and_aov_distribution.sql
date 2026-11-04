-- ******************************************************
--                         CTE
-- ******************************************************

use cosmetics_store;
go

--1) مقارنة إحصائية بين المتوسط الحسابي والوسيط لقيمة الفاتورة ومكونات السلة
---------------------------------------------
with RankedOrders as ( --> CTE بنحسب فيه المئينات الإحصائية لقيم الفواتير
    select 
        final_total,
        total_qty,
        percentile_cont(0.50) within group (order by final_total) over () as [MedianOrderValue], --> percentile_cont(0.50) لحساب الوسيط الحسابي Median لقيمة الفواتير
        percentile_cont(0.25) within group (order by final_total) over () as [P25_OrderValue], --> المئين 25 يعني 25% من الفواتير قيمتها أقل من الرقم ده
        percentile_cont(0.75) within group (order by final_total) over () as [P75_OrderValue], --> المئين 75
        percentile_cont(0.90) within group (order by final_total) over () as [P90_OrderValue] --> المئين 90
    from dbo.FactSalesInvoice
)
select distinct --> distinct عشان منكررش نفس أرقام الإحصائيات مع كل صف
    (select count(*) from dbo.FactSalesInvoice) as [TotalInvoices],
    (select round(avg(final_total), 2) from dbo.FactSalesInvoice) as [MeanOrderValue],
    round(MedianOrderValue, 2) as [MedianOrderValue],
    round(P25_OrderValue, 2) as [25thPercentile],
    round(P75_OrderValue, 2) as [75thPercentile],
    round(P90_OrderValue, 2) as [90thPercentile],
    (select round(avg(total_qty), 2) from dbo.FactSalesInvoice) as [AvgItemsPerBasket] --> متوسط عدد القطع في سلة الشراء
from RankedOrders;

---------------------------------------------
--2) توزيع الفواتير على شرائح وقيم الإنفاق Spend Brackets
---------------------------------------------
select 
    case 
        when final_total < 50 then 'Under 50 EGP' --> تقسيم الفواتير لشرائح إنفاق لمعرفة سلوك الزبائن
        when final_total between 50 and 99.99 then '50 - 99 EGP'
        when final_total between 100 and 199.99 then '100 - 199 EGP'
        when final_total between 200 and 499.99 then '200 - 499 EGP'
        when final_total between 500 and 999.99 then '500 - 999 EGP'
        else '1,000+ EGP (High-Value Orders)' --> الفواتير الكبيرة أعلى من 1000 جنيه
    end as [SpendBracket],
    count(invoice_no) as [OrdersCount],
    round(count(invoice_no) * 100.0 / (select count(*) from dbo.FactSalesInvoice), 2) as [OrdersPct],
    sum(final_total) as [TotalRevenue],
    round(sum(final_total) * 100.0 / (select sum(final_total) from dbo.FactSalesInvoice), 2) as [RevenuePct]
from dbo.FactSalesInvoice
group by 
    case 
        when final_total < 50 then 'Under 50 EGP'
        when final_total between 50 and 99.99 then '50 - 99 EGP'
        when final_total between 100 and 199.99 then '100 - 199 EGP'
        when final_total between 200 and 499.99 then '200 - 499 EGP'
        when final_total between 500 and 999.99 then '500 - 999 EGP'
        else '1,000+ EGP (High-Value Orders)'
    end
order by min(final_total);
go
