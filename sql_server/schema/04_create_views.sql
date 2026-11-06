-- *****************************************************************************
-- 04_create_views.sql
-- طبقة الـ Views التحليلية ومؤشرات الأداء التشخيصية لقاعدة بيانات cosmetics_store
-- *****************************************************************************

use cosmetics_store;
go

-- 1. view خطوط المبيعات والمرتجع الموحدة (موجب للبيع وسالب للمرتجع)
--------------------------------------------------------------------------------
if object_id('dbo.vw_FactSalesLines', 'V') is not null drop view dbo.vw_FactSalesLines;
go
create view dbo.vw_FactSalesLines as
select
    N'Sale' as line_type, --> تمييز نوع السطر كعملية بيع
    si.invoice_no as doc_no, --> رقم الفاتورة
    inv.invoice_date as txn_date, --> تاريخ الحركة
    inv.sale_type, --> نوع المعاملة
    inv.is_retail_sale, --> علامة البيع القطاعي
    si.item_code, --> كود الصنف
    p.item_name, --> اسم الصنف
    p.product_scope, --> نطاق المنتج
    p.product_category, --> قسم المنتج
    si.qty as qty_signed, --> كمية موجبة للبيع
    si.line_final as revenue_signed, --> إيراد موجب للبيع
    si.profit as profit_signed, --> ربح موجب للبيع
    si.line_final - si.profit as cost_signed --> تكلفة موجبة للبيع
from dbo.FactSalesItem si
join dbo.FactSalesInvoice inv on inv.invoice_no = si.invoice_no
join dbo.DimProduct p on p.item_code = si.item_code
union all
select
    N'Return', --> تمييز نوع السطر كمرتجع
    r.return_invoice_no, --> رقم إشعار المرتجع
    ri.return_date, --> تاريخ المرتجع
    N'Retail Return', --> وصف الحركة
    ri.is_retail_sale, --> مرتجع تجزئة
    r.item_code, --> كود الصنف المرتجع
    p.item_name, --> اسم الصنف
    p.product_scope, --> نطاق المنتج
    p.product_category, --> قسم المنتج
    -r.qty, --> كمية سالبة لخصم المرتجع من المبيعات
    r.line_final, --> قيمة سالبة للمرتجع
    r.profit, --> أثر سالب على الربح
    r.line_final - r.profit --> تكلفة البضاعة المرتجعة
from dbo.FactSalesReturnItem r
join dbo.FactSalesReturnInvoice ri on ri.return_invoice_no = r.return_invoice_no
join dbo.DimProduct p on p.item_code = r.item_code;
go

-- 2. view ملخص المصالحة المالية الشاملة للمتجر (Gross vs Retail Net Summary)
--------------------------------------------------------------------------------
if object_id('dbo.vw_StoreNetSalesSummary', 'V') is not null drop view dbo.vw_StoreNetSalesSummary;
go
create view dbo.vw_StoreNetSalesSummary as
select
    (select sum(final_total) from dbo.FactSalesInvoice) as gross_book_sales, --> إجمالي مبيعات الدفاتر قبل أي استبعاد
    (select sum(profit) from dbo.FactSalesInvoice) as gross_book_profit, --> إجمالي أرباح الدفاتر
    (select sum(final_total) from dbo.FactSalesInvoice where is_retail_sale = 0) as non_retail_excluded_sales, --> قيمة الحركات غير التشغيلية المستبعدة (62.4 ألف)
    (select sum(profit) from dbo.FactSalesInvoice where is_retail_sale = 0) as non_retail_excluded_profit, --> أرباح الحركات المستبعدة
    (select sum(final_total) from dbo.FactSalesInvoice where is_retail_sale = 1) as retail_gross_sales, --> إجمالي مبيعات التجزئة (915.7 ألف)
    (select sum(profit) from dbo.FactSalesInvoice where is_retail_sale = 1) as retail_gross_profit, --> إجمالي أرباح التجزئة
    (select sum(final_total) from dbo.FactSalesReturnInvoice) as total_returns, --> إجمالي كل المرتجعات (-13.7 ألف)
    (select sum(profit) from dbo.FactSalesReturnInvoice) as total_returns_profit_impact, --> أثر المرتجعات على الربح
    (select sum(final_total) from dbo.FactSalesInvoice where is_retail_sale = 1)
        + (select sum(final_total) from dbo.FactSalesReturnInvoice) as retail_net_sales, --> صافي مبيعات التجزئة الفعلي (901.9 ألف)
    (select sum(profit) from dbo.FactSalesInvoice where is_retail_sale = 1)
        + (select sum(profit) from dbo.FactSalesReturnInvoice) as retail_net_profit, --> صافي أرباح التجزئة الفعلية (192.5 ألف)
    cast(100.0 * ((select sum(profit) from dbo.FactSalesInvoice where is_retail_sale = 1)
                  + (select sum(profit) from dbo.FactSalesReturnInvoice))
         / nullif((select sum(final_total) from dbo.FactSalesInvoice where is_retail_sale = 1)
                  + (select sum(final_total) from dbo.FactSalesReturnInvoice), 0) as decimal(9, 2)) as retail_net_margin_pct, --> هامش ربح التجزئة الصافي (21.35%)
    (select count(*) from dbo.FactSalesReturnInvoice where original_invoice_status <> N'Found in sales_invoices') as unlinked_return_invoices, --> عدد المرتجعات غير المربوطة (4)
    (select count(*) from dbo.MissingInvoicesLog) as missing_invoice_gaps; --> عدد الفواتير المفقودة في التسلسل (26)
go

-- 3. view مؤشرات الأداء والاتجاهات الشهرية لصافي مبيعات التجزئة (vw_KpiMonthly)
--------------------------------------------------------------------------------
if object_id('dbo.vw_KpiMonthly', 'V') is not null drop view dbo.vw_KpiMonthly;
go
create view dbo.vw_KpiMonthly as
with months as ( --> CTE جدول الشهور الكاملة وأيامها
    select year_month, min(full_date) as month_start, max(days_in_month) as days_in_month
    from dbo.DimDate group by year_month
),
s as ( --> CTE مبيعات التجزئة لكل شهر
    select d.year_month,
           count(*) as invoices, --> عدد فواتير التجزئة
           count(distinct i.invoice_date) as trading_days, --> عدد أيام العمل الفعلية في الشهر
           sum(i.final_total) as gross_sales, --> مبيعات التجزئة قبل المرتجع
           sum(i.profit) as gross_profit --> أرباح التجزئة قبل المرتجع
    from dbo.FactSalesInvoice i
    join dbo.DimDate d on d.full_date = i.invoice_date
    where i.is_retail_sale = 1
    group by d.year_month
),
r as ( --> CTE مرتجعات كل شهر
    select d.year_month,
           count(*) as return_invoices, --> عدد فواتير المرتجع
           sum(x.final_total) as returns_value, --> قيمة المرتجعات بالسالب
           sum(x.profit) as returns_profit --> أثر المرتجعات على الربح
    from dbo.FactSalesReturnInvoice x
    join dbo.DimDate d on d.full_date = x.return_date
    where x.is_retail_sale = 1
    group by d.year_month
)
select
    m.year_month,
    isnull(s.invoices, 0) as invoices,
    isnull(s.trading_days, 0) as trading_days,
    m.days_in_month,
    case when isnull(s.trading_days, 0) < 0.8 * m.days_in_month then 1 else 0 end as is_partial_month, --> تحديد ديناميكي للشهور الجزئية
    isnull(s.gross_sales, 0) as gross_sales,
    isnull(r.returns_value, 0) as returns_value,
    isnull(s.gross_sales, 0) + isnull(r.returns_value, 0) as net_sales, --> صافي المبيعات
    isnull(s.gross_profit, 0) + isnull(r.returns_profit, 0) as net_profit, --> صافي الربح
    cast(100.0 * (isnull(s.gross_profit, 0) + isnull(r.returns_profit, 0))
         / nullif(isnull(s.gross_sales, 0) + isnull(r.returns_value, 0), 0) as decimal(9,2)) as net_margin_pct, --> هامش الربح الصافي
    cast(s.gross_sales / nullif(s.invoices, 0) as decimal(18,2)) as avg_ticket, --> متوسط قيمة الفاتورة AOV
    cast((isnull(s.gross_sales, 0) + isnull(r.returns_value, 0))
         / nullif(s.trading_days, 0) as decimal(18,2)) as net_sales_per_trading_day, --> مبيعات اليوم الواحد
    cast(-100.0 * isnull(r.returns_value, 0) / nullif(s.gross_sales, 0) as decimal(9,2)) as return_rate_pct --> نسبة المرتجعات من مبيعات التجزئة
from months m
left join s on s.year_month = m.year_month
left join r on r.year_month = m.year_month
where s.year_month is not null or r.year_month is not null;
go

-- 4. view مؤشرات أداء وهوامش الأقسام التجميلية (vw_KpiByCategory)
--------------------------------------------------------------------------------
if object_id('dbo.vw_KpiByCategory', 'V') is not null drop view dbo.vw_KpiByCategory;
go
create view dbo.vw_KpiByCategory as
select
    f.product_category, --> القسم التجميلي
    sum(f.qty_signed) as net_units, --> صافي القطع المباعة
    sum(f.revenue_signed) as net_revenue, --> صافي الإيراد
    sum(f.profit_signed) as net_profit, --> صافي الأرباح
    cast(100.0 * sum(f.profit_signed) / nullif(sum(f.revenue_signed), 0) as decimal(9,2)) as margin_pct, --> نسبة مجمل الربح للقسم
    cast(100.0 * sum(f.revenue_signed) / nullif(sum(sum(f.revenue_signed)) over (), 0) as decimal(9,2)) as revenue_share_pct, --> حصة القسم من إجمالي المبيعات
    cast(100.0 * sum(f.profit_signed)  / nullif(sum(sum(f.profit_signed))  over (), 0) as decimal(9,2)) as profit_share_pct --> حصة القسم من إجمالي الأرباح
from dbo.vw_FactSalesLines f
where f.is_retail_sale = 1
group by f.product_category;
go

-- 5. view تصنيف الأصناف حسب المساهمة في الإيراد ABC Pareto Analysis
--------------------------------------------------------------------------------
if object_id('dbo.vw_ProductPerformance', 'V') is not null drop view dbo.vw_ProductPerformance;
go
create view dbo.vw_ProductPerformance as
with p as ( --> CTE صافي مبيعات كل منتج
    select f.item_code,
           max(f.item_name) as item_name,
           max(f.product_scope) as product_scope,
           max(f.product_category) as product_category,
           sum(f.qty_signed) as net_units,
           sum(f.revenue_signed) as net_revenue,
           sum(f.profit_signed) as net_profit
    from dbo.vw_FactSalesLines f
    where f.is_retail_sale = 1
    group by f.item_code
),
ranked as ( --> CTE حساب الترتيب والمجموع التراكمي للإيرادات
    select p.*,
           cast(100.0 * p.net_profit / nullif(p.net_revenue, 0) as decimal(9,2)) as margin_pct,
           rank() over (order by p.net_revenue desc) as revenue_rank,
           sum(case when p.net_revenue > 0 then p.net_revenue else 0 end)
               over (order by p.net_revenue desc, p.item_code
                     rows between unbounded preceding and current row) as cum_revenue, --> الإيراد التراكمي
           sum(case when p.net_revenue > 0 then p.net_revenue else 0 end) over () as total_revenue --> إجمالي الإيرادات
    from p
)
select
    item_code, item_name, product_scope, product_category, net_units, net_revenue, net_profit, margin_pct, revenue_rank,
    cast(100.0 * cum_revenue / nullif(total_revenue, 0) as decimal(9,2)) as cum_revenue_pct,
    case
        when net_revenue <= 0                               then N'-'
        when cum_revenue / nullif(total_revenue, 0) <= 0.80 then N'A' --> فئة A (تحقق أول 80% من الإيرادات)
        when cum_revenue / nullif(total_revenue, 0) <= 0.95 then N'B' --> فئة B (تحقق الـ 15% التالية)
        else N'C' --> فئة C (الـ 5% المتبقية)
    end as abc_class
from ranked;
go

-- 6. view تشخيص حركة الزبائن ومعدل الفاتورة (Traffic vs Ticket Size)
--------------------------------------------------------------------------------
if object_id('dbo.vw_TrafficTicketMonthly', 'V') is not null drop view dbo.vw_TrafficTicketMonthly;
go
create view dbo.vw_TrafficTicketMonthly as
with inv as ( --> CTE عدد الفواتير وأيام العمل شهرياً
    select d.year_month,
           count(*) as invoices,
           count(distinct i.invoice_date) as trading_days,
           sum(i.final_total) as sales
    from dbo.FactSalesInvoice i
    join dbo.DimDate d on d.full_date = i.invoice_date
    where i.is_retail_sale = 1
    group by d.year_month
),
ln as ( --> CTE القطع المباعة وسعر الوحدة والأصناف النشطة
    select d.year_month,
           sum(s.qty) as units,
           sum(s.line_final) as line_sales,
           count(distinct s.item_code) as active_skus
    from dbo.FactSalesItem s
    join dbo.FactSalesInvoice i on i.invoice_no = s.invoice_no
    join dbo.DimDate d on d.full_date = i.invoice_date
    where i.is_retail_sale = 1
    group by d.year_month
)
select
    inv.year_month,
    inv.invoices,
    inv.trading_days,
    cast(1.0 * inv.invoices / nullif(inv.trading_days, 0) as decimal(9,1)) as invoices_per_day, --> عدد الفواتير يومياً (مؤشر Traffic)
    cast(inv.sales / nullif(inv.invoices, 0) as decimal(18,1)) as avg_ticket, --> متوسط قيمة الفاتورة AOV (مؤشر Basket Value)
    cast(ln.units  / nullif(inv.invoices, 0) as decimal(9,2)) as units_per_invoice, --> عدد القطع في كل فاتورة (مؤشر Basket Size)
    cast(ln.line_sales / nullif(ln.units, 0) as decimal(18,1)) as avg_unit_price, --> متوسط سعر بيع القطعة (مؤشر Pricing)
    ln.active_skus as distinct_products_sold --> عدد الأصناف المختلفة التي بيعت في الشهر
from inv
join ln on ln.year_month = inv.year_month;
go

-- 7. view نسبة توفر بضاعة الكتالوج في المخزن شهرياً (Stock Availability Collapse)
--------------------------------------------------------------------------------
if object_id('dbo.vw_StockAvailabilityMonthly', 'V') is not null drop view dbo.vw_StockAvailabilityMonthly;
go
create view dbo.vw_StockAvailabilityMonthly as
with snap as ( --> تاريخ نهاية البيانات
    select max(invoice_date) as snapshot_date from dbo.FactSalesInvoice
),
mv as ( --> تجميع كافة حركات المخزن (مشتريات + مبيعات - مرتجعات)
    select pinv.purchase_date as d, x.item_code, x.qty as q
    from dbo.FactPurchaseItem x
    join dbo.FactPurchaseInvoice pinv on pinv.invoice_no = x.invoice_no
    union all
    select i.invoice_date, s.item_code, -s.qty
    from dbo.FactSalesItem s
    join dbo.FactSalesInvoice i on i.invoice_no = s.invoice_no
    union all
    select r.return_date, x.item_code, x.qty
    from dbo.FactSalesReturnItem x
    join dbo.FactSalesReturnInvoice r on r.return_invoice_no = x.return_invoice_no
    where r.return_date <= (select snapshot_date from snap)
),
mvm as ( --> صافي حركة كل صنف في كل شهر
    select dd.year_month, mv.item_code, sum(mv.q) as net
    from mv
    join dbo.DimDate dd on dd.full_date = mv.d
    group by dd.year_month, mv.item_code
),
first_month as ( --> أول شهر ظهر فيه الصنف
    select item_code, min(year_month) as first_ym from mvm group by item_code
),
grid as ( --> شبكة الشهور والأصناف
    select mo.year_month, p.item_code, p.total_qty as current_stock_qty, isnull(m.net, 0) as net
    from (select distinct year_month from dbo.DimDate) mo
    cross join dbo.DimProduct p
    left join mvm m on m.year_month = mo.year_month and m.item_code = p.item_code
),
stock_at as ( --> حساب رصيد الصنف في نهاية كل شهر بالعكس من الرصيد الحالي
    select g.year_month, g.item_code,
           g.current_stock_qty
             - isnull(sum(g.net) over (partition by g.item_code order by g.year_month
                                       rows between 1 following and unbounded following), 0) as stock_end
    from grid g
)
select
    s.year_month,
    count(*) as catalogue_skus, --> إجمالي أصناف الكتالوج النشطة
    sum(case when s.stock_end >  0 then 1 else 0 end) as in_stock_skus, --> الأصناف المتوفرة
    sum(case when s.stock_end <= 0 then 1 else 0 end) as out_or_negative_skus, --> الأصناف النافدة أو السالبة
    cast(100.0 * sum(case when s.stock_end > 0 then 1 else 0 end) / count(*) as decimal(5,1)) as pct_in_stock --> نسبة التوفر في المخزن
from stock_at s
join first_month f on f.item_code = s.item_code and f.first_ym <= s.year_month
group by s.year_month;
go
