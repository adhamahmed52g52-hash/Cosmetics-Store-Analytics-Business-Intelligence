-- ******************************************************
--                         CTE
-- ******************************************************

use cosmetics_store;
go

--1) تحليل نمط حركة المبيعات وتوزيع الشفتات على مدار 24 ساعة
---------------------------------------------
with HourlyStats as ( --> CTE بنجمع فيه حركة المبيعات لكل ساعة في اليوم
    select 
        order_hour as [HourOfDay],
        count(invoice_no) as [OrderCount],
        sum(final_total) as [HourlyRevenue],
        avg(final_total) as [AvgOrderValue], --> متوسط قيمة الفاتورة في الساعة دي
        case 
            when order_hour between 20 and 23 then 'Evening Peak Shift (20:00 - 23:59)' --> شفت المساء وهو وقت الذروة للمحل
            when order_hour between 0 and 3 then 'Midnight Shift Continuation (00:00 - 03:59)' --> فترة السهر بعد منتصف الليل
            when order_hour between 12 and 19 then 'Daytime / Afternoon Shift (12:00 - 19:59)' --> شفت النهار والظهيرة
            else 'Off-Hours / Morning'
        end as [ShiftSegment]
    from dbo.FactSalesInvoice
    group by order_hour
),
TotalStoreRevenue as ( --> CTE بيحسب إجمالي إيراد المحل عشان نقسم عليه ونطلع النسبة
    select sum(final_total) as [TotalRevenue] from dbo.FactSalesInvoice
)
select 
    h.[HourOfDay],
    h.[ShiftSegment],
    h.[OrderCount],
    h.[HourlyRevenue],
    round(h.[HourlyRevenue] / t.[TotalRevenue] * 100.0, 2) as [RevenueSharePct],
    round(h.[AvgOrderValue], 2) as [AOV],
    dense_rank() over (order by h.[HourlyRevenue] desc) as [RankByRevenue], --> dense_rank لترتيب الساعات تنازلياً حسب الإيراد بدون ما يسيب فجوة في الترتيب
    dense_rank() over (order by h.[OrderCount] desc) as [RankByOrders] --> ترتيب الساعات حسب عدد الفواتير
from HourlyStats as h
cross join TotalStoreRevenue as t --> cross join عشان ندمج رقم إجمالي الإيراد مع كل الساعات
order by h.[HourOfDay];
go
