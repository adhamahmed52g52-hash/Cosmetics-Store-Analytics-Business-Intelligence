use cosmetics_store;
go

--1) ملخص تقييم المخزون المالي حسب الأقسام Category
---------------------------------------------
select 
    product_category as [Category],
    count(item_code) as [SKUCount],
    sum(total_qty) as [TotalUnitsInStock],
    sum(case when stock_cost_valuation > 0 then stock_cost_valuation else 0 end) as [PositiveValuationEGP], --> تجميع قيمة الأصناف ذات التقييم الموجب
    sum(case when stock_cost_valuation < 0 then stock_cost_valuation else 0 end) as [NegativeValuationImpactEGP], --> أثر الأصناف السالبة
    sum(stock_cost_valuation) as [NetValuationEGP], --> صافي التقييم المالي للقسم
    round(sum(stock_cost_valuation) * 100.0 / (select sum(stock_cost_valuation) from dbo.DimProduct), 2) as [NetValuationSharePct],
    round(avg(avg_purchase_price), 2) as [AvgCostPerItem],
    round(avg(sell_price), 2) as [AvgRetailPrice]
from dbo.DimProduct
group by product_category
order by NetValuationEGP desc;
go

---------------------------------------------
--2) تقييم المخزون حسب نطاق المنتجات Product Scope
---------------------------------------------
select 
    product_scope as [ProductScope],
    count(item_code) as [SKUCount],
    sum(total_qty) as [TotalUnitsInStock],
    sum(stock_cost_valuation) as [NetValuationEGP],
    round(sum(stock_cost_valuation) * 100.0 / (select sum(stock_cost_valuation) from dbo.DimProduct), 2) as [ValuationSharePct]
from dbo.DimProduct
group by product_scope
order by NetValuationEGP desc;
go

---------------------------------------------
--3) فحص المنتجات ذات الرصيد السالب 84 صنف والأثر المالي
---------------------------------------------
select 
    item_code,
    item_name,
    product_scope,
    product_category,
    total_qty as [NegativeQty],
    avg_purchase_price as [UnitCost],
    sell_price as [RetailPrice],
    stock_cost_valuation as [ValuationImpact],
    case 
        when avg_purchase_price = 0 then 'Negative quantity with zero purchase cost, cannot be valued, needs audit' --> أصناف سالبة بدون تكلفة شراء
        else 'Negative stock with unit cost (exposure: ' + cast(round(stock_cost_valuation, 2) as nvarchar(50)) + ' EGP)'
    end as [AuditNote]
from dbo.DimProduct
where total_qty < 0 --> الأصناف اللي رصيدها سالب ومحتاجة جرد ومراجعة
order by stock_cost_valuation asc;
go

---------------------------------------------
--4) الحالة العامة للمخزون والتوزيع المالي للأصناف
---------------------------------------------
select 
    case 
        when total_qty > 0 then 'Positive Stock (Healthy Inventory)'
        when total_qty = 0 then 'Zero Stock (Out of Stock)'
        else 'Negative Stock (Discrepancy / Backorder)'
    end as [StockStatus],
    count(item_code) as [SKUCount],
    round(count(item_code) * 100.0 / (select count(*) from dbo.DimProduct), 2) as [SKUSharePct],
    sum(total_qty) as [TotalUnits],
    sum(stock_cost_valuation) as [ValuationEGP]
from dbo.DimProduct
group by 
    case 
        when total_qty > 0 then 'Positive Stock (Healthy Inventory)'
        when total_qty = 0 then 'Zero Stock (Out of Stock)'
        else 'Negative Stock (Discrepancy / Backorder)'
    end
order by ValuationEGP desc;
go
