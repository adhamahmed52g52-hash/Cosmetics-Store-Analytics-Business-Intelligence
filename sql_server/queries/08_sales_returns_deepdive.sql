use cosmetics_store;
go

--1) مؤشر معدل الاسترداد المالي العام للمرتجعات Return Rate KPI
---------------------------------------------
select 
    (select sum(final_total) from dbo.FactSalesInvoice) as [GrossSalesRevenue],
    (select abs(sum(final_total)) from dbo.FactSalesReturnInvoice) as [SalesReturnsValue],
    round((select abs(sum(final_total)) from dbo.FactSalesReturnInvoice) / 
          (select sum(final_total) from dbo.FactSalesInvoice) * 100.0, 2) as [ReturnRatePct], --> نسبة إجمالي قيمة المرتجعات من المبيعات
    (select count(*) from dbo.FactSalesInvoice) as [SalesOrdersCount],
    (select count(*) from dbo.FactSalesReturnInvoice) as [ReturnOrdersCount];

---------------------------------------------
--2) أعلى 10 منتجات تم إرجاعها واسترداد قيمتها
---------------------------------------------
select top 10
    r.item_code,
    r.item_name,
    p.product_category,
    sum(r.qty) as [UnitsReturned],
    abs(sum(r.line_final)) as [TotalRefundValue], --> abs عشان قيمة المرتجع بالسالب وإحنا عاوزين المبلغ كرقم موجب
    abs(sum(r.profit)) as [ProfitImpact],
    dense_rank() over (order by abs(sum(r.line_final)) desc) as [RefundRank] --> ترتيب الأصناف حسب قيمة المبالغ المستردة
from dbo.FactSalesReturnItem as r
left join dbo.DimProduct as p
    on r.item_code = p.item_code
group by r.item_code, r.item_name, p.product_category
order by TotalRefundValue desc;

---------------------------------------------
--3) فحص مدى ارتباط فواتير المرتجعات بفواتير البيع الأصلية
---------------------------------------------
select 
    case 
        when s.invoice_no is not null then 'Linked to Valid Sales Invoice'
        else 'Unlinked / Manual Return (Cut-off Lag)'
    end as [TraceabilityStatus],
    count(r.return_invoice_no) as [ReturnInvoicesCount],
    abs(sum(r.final_total)) as [RefundsTotal]
from dbo.FactSalesReturnInvoice as r
left join dbo.FactSalesInvoice as s
    on r.original_invoice_no = s.invoice_no --> ربط المرتجع بفاتورة البيع الأصلية لمعرفة هل مسجلة في نفس الفترة
group by 
    case 
        when s.invoice_no is not null then 'Linked to Valid Sales Invoice'
        else 'Unlinked / Manual Return (Cut-off Lag)'
    end;
go
