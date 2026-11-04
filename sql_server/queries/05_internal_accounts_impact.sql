use cosmetics_store;
go

--1) مقارنة شرائح العملاء الأربعة المعتمدة Customer Segments
---------------------------------------------
select 
    customer_type as [CustomerSegment],
    count(invoice_no) as [InvoicesCount],
    round(count(invoice_no) * 100.0 / (select count(*) from dbo.FactSalesInvoice), 2) as [InvoicesSharePct],
    sum(final_total) as [TotalRevenue],
    round(sum(final_total) * 100.0 / (select sum(final_total) from dbo.FactSalesInvoice), 2) as [RevenueSharePct],
    round(avg(final_total), 2) as [AverageOrderValue],
    sum(profit) as [TotalProfit],
    round(sum(profit) / nullif(sum(final_total), 0) * 100.0, 2) as [ProfitMarginPct]
from dbo.FactSalesInvoice
group by customer_type
order by TotalRevenue desc;
go

---------------------------------------------
--2) تفاصيل فواتير الحسابات المسجلة Commercial و Partner و Settlement
---------------------------------------------
select 
    s.customer_type as [CustomerSegment],
    s.acct_no as [AccountNo],
    isnull(a.acct_name, s.account_name) as [AccountName], --> isnull لجلب اسم الحساب من جدول الحسابات ولو مش موجود ياخده من الفاتورة
    s.internal_account_status as [InternalStatus],
    count(s.invoice_no) as [InvoicesCount],
    sum(s.final_total) as [TotalRevenue],
    round(sum(s.final_total) * 100.0 / (select sum(final_total) from dbo.FactSalesInvoice where customer_type <> 'Walk-in Retail'), 2) as [ShareOfAccountRevenuePct],
    sum(s.profit) as [TotalProfit],
    round(sum(s.profit) / nullif(sum(s.final_total), 0) * 100.0, 2) as [ProfitMarginPct]
from dbo.FactSalesInvoice as s
left join dbo.DimAccount as a
    on s.acct_no = a.acct_no
where s.customer_type <> 'Walk-in Retail' --> استبعاد مبيعات القطاعي والتركيز على الحسابات الخاصة
group by s.customer_type, s.acct_no, a.acct_name, s.account_name, s.internal_account_status
order by TotalRevenue desc;
go

---------------------------------------------
--3) تحليل الحساسية لأداء المحل مع وبدون فواتير الشريك الداخلي
---------------------------------------------
select 
    case 
        when customer_type = 'Internal Partner' then 'Internal Partner Transactions'
        when customer_type = 'Walk-in Retail' then 'Walk-in Retail Customers'
        when customer_type = 'Registered Commercial' then 'Registered Commercial Clients'
        when customer_type = 'Supplier Settlement' then 'Supplier Settlement Entries'
    end as [OperatingChannel],
    count(invoice_no) as [InvoicesCount],
    sum(final_total) as [TotalRevenue],
    round(sum(final_total) * 100.0 / (select sum(final_total) from dbo.FactSalesInvoice), 2) as [RevenueSharePct],
    sum(profit) as [TotalProfit],
    round(avg(final_total), 2) as [AOV]
from dbo.FactSalesInvoice
group by customer_type
order by TotalRevenue desc;
go
