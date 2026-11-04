-- ******************************************************
--                         CTE
-- ******************************************************

use cosmetics_store;
go

--1) تحليل الاتجاهات الشهرية للمبيعات والأرباح وإجمالي المرتجعات
---------------------------------------------
with MonthlySales as ( --> CTE جدول مؤقت بنجهز فيه مبيعات كل شهر
    select 
        format(invoice_date, 'yyyy-MM') as [YearMonth], --> بنحول التاريخ لصيغة سنة وشهر
        count(invoice_no) as [TotalOrders], --> عدد الفواتير في الشهر
        sum(final_total) as [GrossSales], --> إجمالي المبيعات قبل خصم المرتجعات
        sum(profit) as [GrossProfit] --> إجمالي مجمل الربح
    from dbo.FactSalesInvoice
    group by format(invoice_date, 'yyyy-MM')
),
MonthlyReturns as ( --> CTE بنحسب فيه مرتجعات كل شهر
    select 
        format(return_date, 'yyyy-MM') as [YearMonth],
        count(return_invoice_no) as [ReturnOrders],
        abs(sum(final_total)) as [ReturnsValue], --> abs عشان قيمة المرتجع متسجلة بالسالب وإحنا عاوزينها موجبة
        abs(sum(profit)) as [ReturnsProfitLoss]
    from dbo.FactSalesReturnInvoice
    group by format(return_date, 'yyyy-MM')
)
select 
    s.[YearMonth],
    case 
        when s.[YearMonth] in ('2025-11', '2026-09') then 'Partial Month' --> الشهور دي مش كاملة لأن التسجيل بدأ في نص الشهر
        else 'Full Month'
    end as [OperatingStatus],
    s.[TotalOrders],
    s.[GrossSales],
    isnull(r.[ReturnsValue], 0) as [ReturnsValue], --> isnull عشان لو الشهر مفيش فيه مرتجعات يرجع 0 بدل Null
    s.[GrossSales] - isnull(r.[ReturnsValue], 0) as [NetSales], --> صافي المبيعات بعد طرح المرتجعات
    s.[GrossProfit],
    round(s.[GrossProfit] / nullif(s.[GrossSales], 0) * 100.0, 2) as [MarginPct] --> nullif عشان نتجنب القسمة على صفر لو المبيعات صفر
from MonthlySales as s
left join MonthlyReturns as r
    on s.[YearMonth] = r.[YearMonth] --> ربط المبيعات بالمرتجعات لنفس الشهر
order by s.[YearMonth]; --> ترتيب الشهور تصاعدي من الأقدم للأحدث
go
