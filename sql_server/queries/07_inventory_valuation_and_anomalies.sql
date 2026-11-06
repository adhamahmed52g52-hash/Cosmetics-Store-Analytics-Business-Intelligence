-- *****************************************************************************
-- 07_inventory_valuation_and_anomalies.sql
-- تقرير التقييم المالي للمخزون وفحص شذوذ الأصناف ذات الرصيد السالب (84 صنف)
-- *****************************************************************************

use cosmetics_store;
go

-- 1) تقييم المخزون المالي الإجمالي حسب الأقسام التجميلية
--------------------------------------------------------------------------------
select 
    product_category as [ProductCategory], --> اسم القسم التجميلي
    count(item_code) as [TotalSKUCount], --> إجمالي عدد أصناف القسم
    sum(total_qty) as [TotalStockUnits], --> إجمالي عدد القطع الموجودة في المخزن
    sum(case when stock_cost_valuation > 0 then stock_cost_valuation else 0 end) as [PositiveValuationEGP], --> قيمة الأصناف ذات الرصيد الموجب
    sum(case when stock_cost_valuation < 0 then stock_cost_valuation else 0 end) as [NegativeValuationImpactEGP], --> الأثر السلبي للأصناف ذات الرصيد السالب
    sum(stock_cost_valuation) as [NetValuationEGP], --> صافي التقييم المالي بالتكلفة
    round(sum(stock_cost_valuation) * 100.0 / (select sum(stock_cost_valuation) from dbo.DimProduct), 2) as [ValuationSharePct], --> نسبة القسم من قيمة بضاعة المحل
    round(avg(avg_purchase_price), 2) as [AverageUnitCost], --> متوسط سعر شراء القطعة في القسم
    round(avg(sell_price), 2) as [AverageRetailPrice] --> متوسط سعر بيع القطعة للجمهور
from dbo.DimProduct
group by product_category
order by NetValuationEGP desc;
go

-- 2) تقييم المخزون حسب نطاق المنتجات (Product Scope)
--------------------------------------------------------------------------------
select 
    product_scope as [ProductScope], --> نطاق المنتج (تجميل أساسي مقابل عناية شخصية أو إكسسوارات)
    count(item_code) as [TotalSKUCount], --> عدد الأصناف
    sum(total_qty) as [TotalStockUnits], --> إجمالي عدد القطع بالمخزن
    sum(stock_cost_valuation) as [NetValuationEGP], --> صافي التقييم المالي بالتكلفة
    round(sum(stock_cost_valuation) * 100.0 / (select sum(stock_cost_valuation) from dbo.DimProduct), 2) as [ValuationSharePct] --> حصة النطاق من قيمة المخزون
from dbo.DimProduct
group by product_scope
order by NetValuationEGP desc;
go

-- 3) تدقيق الأصناف ذات الرصيد السالب (84 صنف شاذ في المخزن)
--------------------------------------------------------------------------------
select 
    item_code as [ItemCode], --> كود الصنف
    item_name as [ItemName], --> اسم الصنف
    product_scope as [ProductScope], --> نطاق المنتج
    product_category as [ProductCategory], --> قسم المنتج
    total_qty as [NegativeStockUnits], --> الكمية السالبة المسجلة في النظام
    avg_purchase_price as [UnitCostEGP], --> سعر تكلفة الشراء
    sell_price as [RetailSellingPriceEGP], --> سعر البيع للجمهور
    stock_cost_valuation as [ValuationImpactEGP], --> الأثر المالي بالسالب على تقييم المخزون
    case 
        when avg_purchase_price = 0 then 'Negative quantity with zero cost (Cannot be valued; needs immediate physical count)' --> أصناف سالبة بدون تكلفة مسجلة
        else 'Negative stock with known cost (Exposure: ' + cast(round(stock_cost_valuation, 2) as nvarchar(50)) + ' EGP)' --> أصناف سالبة لها تكلفة مسجلة
    end as [AuditNote] --> الملاحظة الرقابية
from dbo.DimProduct
where total_qty < 0 --> فلترة الأصناف ذات الرصيد السالب فقط
order by stock_cost_valuation asc; --> ترتيب الأصناف من الأكثر تأثيراً بالسالب
go

-- 4) ملخص صحة المخزون وحالة الأرصدة الثلاث (موجب، صفر، سالب)
--------------------------------------------------------------------------------
select 
    case 
        when total_qty > 0 then 'Positive Stock (Healthy Inventory)' --> رصيد موجب متوفر
        when total_qty = 0 then 'Zero Stock (Completely Out-of-Stock)' --> رصيد صفر نافد تماماً
        else 'Negative Stock (Operational Inventory Anomaly)' --> رصيد سالب يحتاج تسوية جرد
    end as [StockHealthStatus],
    count(item_code) as [SKUCount], --> عدد الأصناف في كل حالة
    round(count(item_code) * 100.0 / (select count(*) from dbo.DimProduct), 2) as [SKUSharePct], --> نسبة الأصناف المئوية
    sum(total_qty) as [TotalStockUnits], --> إجمالي عدد القطع
    sum(stock_cost_valuation) as [TotalValuationAtCost] --> إجمالي القيمة بالتكلفة
from dbo.DimProduct
group by 
    case 
        when total_qty > 0 then 'Positive Stock (Healthy Inventory)'
        when total_qty = 0 then 'Zero Stock (Completely Out-of-Stock)'
        else 'Negative Stock (Operational Inventory Anomaly)'
    end
order by TotalValuationAtCost desc;
go
