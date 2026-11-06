-- *****************************************************************************
-- 02_hourly_shopping_patterns.sql
-- تحليل نمط حركة المبيعات وتوزيع الشفتات وساعات الذروة على مدار 24 ساعة
-- *****************************************************************************

use cosmetics_store;
go

-- 1) تحليل سلوك تسوق العملاء وساعات الذروة التشغيلية
--------------------------------------------------------------------------------
with HourlyRetailStats as ( --> CTE جدول مؤقت بنجمع فيه حركة مبيعات التجزئة لكل ساعة من ساعات اليوم
    select 
        order_hour as [HourOfDay], --> ساعة إجراء الفاتورة من 0 إلى 23
        count(invoice_no) as [OrderCount], --> عدد الفواتير المنفذة في هذه الساعة
        sum(final_total) as [HourlyRevenue], --> إجمالي الإيراد المحقق في هذه الساعة
        avg(final_total) as [AvgOrderValue], --> متوسط قيمة الفاتورة في هذه الساعة
        case 
            when order_hour between 20 and 23 then 'Evening Peak Shift (20:00 - 23:59)' --> شفت المساء وهو فترة الذروة القصوى للمحل
            when order_hour between 0 and 3 then 'Midnight Shift Continuation (00:00 - 03:59)' --> فترة السهر بعد منتصف الليل
            when order_hour between 12 and 19 then 'Daytime / Afternoon Shift (12:00 - 19:59)' --> شفت الظهيرة وفترة ما بعد الظهر
            else 'Off-Hours / Morning' --> ساعات الصباح الباكر وقبل فتح المحل
        end as [ShiftSegment] --> تقسيم ساعات اليوم لشفتات تشغيلية
    from dbo.FactSalesInvoice
    where is_retail_sale = 1 --> استبعاد الحركات غير التشغيلية والتركيز على مبيعات الجمهور
    group by order_hour
),
TotalRetailStoreRevenue as ( --> CTE بيحسب إجمالي إيراد التجزئة الكلي عشان نقسم عليه ونطلع النسبة المئوية
    select sum(final_total) as [TotalRevenue]
    from dbo.FactSalesInvoice
    where is_retail_sale = 1
)
select 
    h.[HourOfDay] as [HourOfDay], --> الساعة من 0 لـ 23
    h.[ShiftSegment] as [ShiftSegment], --> اسم الشفت التشغيلي
    h.[OrderCount] as [OrdersCount], --> إجمالي عدد الفواتير
    h.[HourlyRevenue] as [HourlyRevenue], --> إجمالي إيراد الساعة
    round(h.[HourlyRevenue] / t.[TotalRevenue] * 100.0, 2) as [RevenueSharePct], --> النسبة المئوية لمساهمة الساعة في إيراد المحل
    round(h.[AvgOrderValue], 2) as [AverageTicketValue], --> متوسط قيمة الفاتورة في الساعة
    dense_rank() over (order by h.[HourlyRevenue] desc) as [RankByRevenue], --> ترتيب الساعات تنازلياً حسب الإيراد بدون فجوات
    dense_rank() over (order by h.[OrderCount] desc) as [RankByOrders] --> ترتيب الساعات حسب عدد الفواتير وحركة الزبائن
from HourlyRetailStats h
cross join TotalRetailStoreRevenue t --> دمج إجمالي الإيراد كسطر ثابت مع كل الساعات
order by h.[HourOfDay]; --> ترتيب الساعات تسلسلياً على مدار اليوم
go
