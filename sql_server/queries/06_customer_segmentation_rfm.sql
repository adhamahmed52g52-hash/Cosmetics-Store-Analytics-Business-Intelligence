-- ******************************************************
--                         CTE
-- ******************************************************

use cosmetics_store;
go

--1) تحليل سجل ومشتريات العملاء والحسابات المسجلة RFM Profile
---------------------------------------------
with AccountRFM as ( --> CTE بنحسب فيه مقاييس الـ RFM لكل حساب مسجل
    select 
        s.acct_no,
        isnull(a.acct_name, s.account_name) as [AccountName], --> isnull لجلب اسم العميل من جدول الحسابات أو الفاتورة
        s.customer_type as [CustomerSegment],
        isnull(a.nature, N'غير محدد') as [AccountNature],
        s.internal_account_status as [InternalStatus],
        max(s.invoice_date) as [LastPurchaseDate], --> تاريخ آخر شراء للعميل
        datediff(day, max(s.invoice_date), '2026-09-14') as [RecencyDays], --> datediff بيحسب الفرق بالأيام بين آخر شراء وتاريخ نهاية البيانات 2026-09-14
        count(s.invoice_no) as [Frequency], --> Frequency عدد مرات الشراء والأوردرات
        sum(s.final_total) as [MonetaryTotal], --> Monetary إجمالي المبالغ اللي دفعها العميل
        sum(s.profit) as [TotalProfit],
        avg(s.final_total) as [AvgOrderValue] --> متوسط قيمة الفاتورة
    from dbo.FactSalesInvoice as s
    left join dbo.DimAccount as a
        on s.acct_no = a.acct_no
    where s.customer_type <> 'Walk-in Retail' --> استبعاد مبيعات القطاعي والتركيز على الحسابات الخاصة
    group by s.acct_no, a.acct_name, s.account_name, s.customer_type, a.nature, s.internal_account_status
)
select 
    acct_no,
    AccountName,
    CustomerSegment,
    AccountNature,
    InternalStatus,
    LastPurchaseDate,
    RecencyDays,
    Frequency,
    MonetaryTotal,
    TotalProfit,
    round(AvgOrderValue, 2) as [AvgOrderValue],
    dense_rank() over (order by MonetaryTotal desc) as [SpendRank] --> ترتيب العملاء حسب إجمالي الصرف
from AccountRFM
order by SpendRank;
go
