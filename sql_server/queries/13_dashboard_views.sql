-- *****************************************************************************
-- 13_dashboard_views.sql
-- *****************************************************************************

use cosmetics_store;
go

-- 1) View مبيعات أيام الأسبوع ونشاط التجزئة اليومي
--------------------------------------------------------------------------------
if object_id('dbo.vw_SalesByWeekday', 'V') is not null drop view dbo.vw_SalesByWeekday;
go
create view dbo.vw_SalesByWeekday as
select
    d.weekday_name, --> اسم يوم الأسبوع بالإنجليزية من التقويم المعتمد
    case d.weekday_no --> ترتيب أيام الأسبوع وفقاً للتقويم المصري: الأحد (1) إلى السبت (7) ومستقل عن DATEFIRST واللغة
        when 7 then 1 -- Sunday (الأحد)
        when 1 then 2 -- Monday (الإثنين)
        when 2 then 3 -- Tuesday (الثلاثاء)
        when 3 then 4 -- Wednesday (الأربعاء)
        when 4 then 5 -- Thursday (الخميس)
        when 5 then 6 -- Friday (الجمعة)
        when 6 then 7 -- Saturday (السبت)
    end as weekday_no,
    count(distinct f.txn_date) as trading_days, --> عدد أيام التداول الفعلية في هذا اليوم
    count(distinct case when f.line_type = N'Sale' then f.doc_no end) as invoices, --> حصر فواتير المبيعات الحقيقية فقط واستبعاد أرقام المرتجعات
    sum(f.revenue_signed) as net_sales, --> صافي المبيعات بعد خصم المرتجعات
    sum(f.profit_signed) as net_profit, --> صافي الأرباح بعد خصم المرتجعات
    cast(sum(f.revenue_signed) * 1.0 / nullif(count(distinct f.txn_date), 0) as decimal(18, 2)) as sales_per_trading_day --> معدل المبيعات لكل يوم عمل
from dbo.vw_FactSalesLines f
join dbo.DimDate d on d.full_date = f.txn_date
where f.is_retail_sale = 1 --> التركيز على مبيعات التجزئة الحقيقية
group by d.weekday_name, d.weekday_no;
go

-- 2) View تقييم صحة وحركة المخزون وتصنيف الركود
--------------------------------------------------------------------------------
if object_id('dbo.vw_InventoryHealth', 'V') is not null drop view dbo.vw_InventoryHealth;
go
create view dbo.vw_InventoryHealth as
with ref as ( --> CTE تحديد أحدث تاريخ بيع تجزئة في البيانات كنقطة مرجعية
    select max(invoice_date) as ref_date
    from dbo.FactSalesInvoice
    where is_retail_sale = 1
),
sales_summary as ( --> CTE تجميع تاريخ آخر بيع والكميات المباعة في آخر 90 يوماً لكل صنف
    select
        si.item_code,
        max(inv.invoice_date) as last_sale_date, --> أحدث تاريخ بيع للصنف
        sum(case when inv.invoice_date > dateadd(day, -90, ref.ref_date)
                 then si.qty else 0 end) as units_last_90d --> الوحدات المباعة في آخر 90 يوماً
    from dbo.FactSalesItem si
    join dbo.FactSalesInvoice inv on si.invoice_no = inv.invoice_no
    cross join ref
    where inv.is_retail_sale = 1 --> مبيعات التجزئة فقط
    group by si.item_code
)
select
    p.item_code, --> كود الصنف
    p.item_name, --> اسم الصنف
    p.product_category, --> القسم التجميلي
    p.total_qty as stock_qty, --> رصيد المخزن الحالي
    p.stock_cost_valuation as stock_value_at_cost, --> تقييم المخزون بالتكلفة
    s.last_sale_date, --> تاريخ آخر حركة بيع
    isnull(s.units_last_90d, 0) as units_last_90d, --> عدد القطع المباعة في آخر 90 يوم
    case --> تصنيف حالة المخزون
        when s.last_sale_date is null                            then 'Never sold' --> بضاعة راكدة لم يباع منها أي قطعة
        when s.last_sale_date <= dateadd(day, -90, ref.ref_date) then 'No sales 90d' --> لم تباع خلال آخر 90 يوماً
        when p.total_qty > (s.units_last_90d / 3.0) * 12         then 'Overstock' --> مخزون فائض يتجاوز مبيعات سنة
        when p.total_qty > (s.units_last_90d / 3.0) * 6          then 'Slow' --> مخزون بطيء الحركة يتجاوز مبيعات 6 أشهر
        else 'Healthy' --> مخزون نشط ومناسب لمعدل السحب
    end as stock_status
from dbo.DimProduct p
left join sales_summary s on p.item_code = s.item_code
cross join ref
where p.total_qty > 0; --> الأصناف ذات الرصيد الموجب المتوفرة للبيع
go
