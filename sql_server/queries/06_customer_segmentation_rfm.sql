-- *****************************************************************************
-- 06_customer_segmentation_rfm.sql
-- تحليل سجل العملاء المسجلين RFM Profile والمقارنة مع زبائن الكاش اليوميين
-- *****************************************************************************

use cosmetics_store;
go

-- 1) تحليل RFM لعملاء التجزئة والتجاريين المسجلين بالاسم
--------------------------------------------------------------------------------
with ReferenceDate as ( --> CTE تحديد تاريخ نهاية فترة البيانات للمقارنة الزمنية
    select max(invoice_date) as [MaxSnapshotDate] from dbo.FactSalesInvoice
),
CustomerRFMMetrics as ( --> CTE حساب أبعاد الـ RFM الثلاثة: الحداثة Recency، التكرار Frequency، القيمة المالية Monetary
    select 
        s.acct_no as [AccountNo], --> رقم الحساب في الدليل
        isnull(a.acct_name, s.account_name) as [CustomerName], --> اسم العميل
        a.account_classification as [AccountClassification], --> تصنيف الحساب
        max(s.invoice_date) as [LastPurchaseDate], --> تاريخ آخر عملية شراء نفذها العميل
        datediff(day, max(s.invoice_date), (select [MaxSnapshotDate] from ReferenceDate)) as [RecencyInDays], --> عدد الأيام منذ آخر شراء
        count(s.invoice_no) as [FrequencyOrdersCount], --> تكرار الشراء وعدد الفواتير
        sum(s.final_total) as [MonetaryTotalSpend], --> إجمالي المبالغ المنفقة من العميل
        sum(s.profit) as [TotalProfitGenerated], --> إجمالي الأرباح المحققة من العميل
        avg(s.final_total) as [AverageOrderValue] --> متوسط قيمة فاتورة العميل
    from dbo.FactSalesInvoice s
    left join dbo.DimAccount a on s.acct_no = a.acct_no
    where s.is_retail_sale = 1 and s.sale_type = 'Named customer' --> حصر التحليل على العملاء الحقيقيين فقط
    group by s.acct_no, a.acct_name, s.account_name, a.account_classification
)
select 
    [AccountNo], --> رقم الحساب
    [CustomerName], --> اسم العميل
    [AccountClassification], --> التصنيف
    [LastPurchaseDate], --> تاريخ آخر شراء
    [RecencyInDays], --> الحداثة بالأيام
    [FrequencyOrdersCount], --> عدد الأوردرات
    [MonetaryTotalSpend], --> إجمالي الصرف
    [TotalProfitGenerated], --> إجمالي الأرباح
    round([AverageOrderValue], 2) as [AverageTicketValue], --> متوسط الفاتورة
    round([TotalProfitGenerated] / nullif([MonetaryTotalSpend], 0) * 100.0, 2) as [CustomerProfitMarginPct], --> نسبة الربحية من هذا العميل
    dense_rank() over (order by [MonetaryTotalSpend] desc) as [SpendRank] --> ترتيب العملاء حسب إجمالي الصرف
from CustomerRFMMetrics
order by [SpendRank]; --> العرض من العميل الأكبر إنفاقاً للأقل
go

-- 2) مقارنة قاعدة عملاء التجزئة: العملاء المسجلون مقابل زبائن الكاش العابرين (Walk-in)
--------------------------------------------------------------------------------
select 
    s.sale_type as [CustomerSegment], --> الشريحة (زبائن كاش بدون حساب مقابل عملاء مسجلين)
    count(s.invoice_no) as [OrdersCount], --> عدد الفواتير
    round(count(s.invoice_no) * 100.0 / (select count(*) from dbo.FactSalesInvoice where is_retail_sale = 1), 2) as [OrdersSharePct], --> نسبة عدد الفواتير من مبيعات التجزئة
    sum(s.final_total) as [TotalRevenue], --> إجمالي الإيراد المحقق
    round(sum(s.final_total) * 100.0 / (select sum(final_total) from dbo.FactSalesInvoice where is_retail_sale = 1), 2) as [RevenueSharePct], --> نسبة المساهمة في إيراد التجزئة
    round(avg(s.final_total), 2) as [AverageTicketValue], --> متوسط قيمة الفاتورة
    sum(s.profit) as [TotalProfit], --> مجمل الربح
    round(sum(s.profit) / nullif(sum(s.final_total), 0) * 100.0, 2) as [ProfitMarginPct] --> نسبة مجمل الربح
from dbo.FactSalesInvoice s
where s.is_retail_sale = 1 --> مبيعات التجزئة فقط
group by s.sale_type;
go
