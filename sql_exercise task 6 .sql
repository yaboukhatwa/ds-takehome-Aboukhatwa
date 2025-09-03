-- =============================================================================
-- SQL Exercise Solutions: Procurement & Supply Chain Analytics
-- =============================================================================
-- This file contains SQL queries to analyze supplier performance, delivery patterns,
-- price anomalies, and operational metrics for a procurement dataset.
-- 
-- Dataset Tables:
-- - suppliers: Company information and ratings
-- - purchase_orders: Order details with logistics info
-- - deliveries: Actual delivery outcomes and delays  
-- - price_lists: Supplier pricing with validity periods
-- - products: Product catalog with specifications
-- 
-- Analysis Period: April 2025 to June 2025 (validation window)
-- =============================================================================

-- =============================================================================
-- QUERY 1: Monthly Delivery Performance by Shipping Method
-- =============================================================================
-- This helps operations teams understand seasonal patterns and identify
-- which shipping methods are most reliable month-to-month

WITH monthly_performance AS (
    -- Calculate late delivery rates for each month and shipping method
    SELECT 
        strftime('%Y-%m', po.order_date) as order_month,
        po.ship_mode,
        COUNT(*) as total_orders,
        SUM(d.late_delivery) as late_orders,
        ROUND(100.0 * SUM(d.late_delivery) / COUNT(*), 2) as late_rate_pct
    FROM purchase_orders po
    JOIN deliveries d ON po.order_id = d.order_id
    WHERE po.order_date >= '2025-04-01' 
        AND po.order_date <= '2025-06-30'
        AND d.cancelled = 0  -- Focus only on completed deliveries
    GROUP BY strftime('%Y-%m', po.order_date), po.ship_mode
)
SELECT 
    order_month,
    COALESCE(ship_mode, 'ALL_METHODS') as shipping_method,
    total_orders,
    late_orders,
    late_rate_pct
FROM monthly_performance

UNION ALL

-- Add overall monthly performance across all shipping methods for comparison
SELECT 
    strftime('%Y-%m', po.order_date) as order_month,
    'ALL_METHODS' as shipping_method,
    COUNT(*) as total_orders,
    SUM(d.late_delivery) as late_orders,
    ROUND(100.0 * SUM(d.late_delivery) / COUNT(*), 2) as late_rate_pct
FROM purchase_orders po
JOIN deliveries d ON po.order_id = d.order_id
WHERE po.order_date >= '2025-04-01' 
    AND po.order_date <= '2025-06-30'
    AND d.cancelled = 0
GROUP BY strftime('%Y-%m', po.order_date)

ORDER BY order_month, shipping_method;

-- =============================================================================
-- QUERY 2: Top Suppliers by Volume with Performance Metrics
-- =============================================================================
-- Identifies our biggest suppliers and how reliable they are - crucial for
-- strategic supplier relationship management and contract negotiations

WITH supplier_performance AS (
    SELECT 
        s.supplier_id,
        s.name as supplier_name,
        s.country as supplier_country,
        s.preferred as is_preferred_supplier,
        s.rating as supplier_rating,
        COUNT(*) as total_orders,
        SUM(po.qty) as total_volume_units,
        SUM(d.late_delivery) as late_deliveries,
        ROUND(100.0 * SUM(d.late_delivery) / COUNT(*), 2) as late_rate_pct,
        ROUND(AVG(d.delay_days), 2) as avg_delay_days
    FROM purchase_orders po
    JOIN deliveries d ON po.order_id = d.order_id
    JOIN suppliers s ON po.supplier_id = s.supplier_id
    WHERE po.order_date >= '2025-04-01' 
        AND po.order_date <= '2025-06-30'
        AND d.cancelled = 0
    GROUP BY s.supplier_id, s.name, s.country, s.preferred, s.rating
)
SELECT 
    supplier_id,
    supplier_name,
    supplier_country,
    is_preferred_supplier,
    supplier_rating,
    total_volume_units,
    total_orders,
    late_deliveries,
    late_rate_pct,
    avg_delay_days
FROM supplier_performance
ORDER BY total_volume_units DESC
LIMIT 5;

-- =============================================================================
-- QUERY 3: Supplier Historical Performance (90-Day Rolling Window)
-- =============================================================================
-- For each order, this calculates how the supplier performed in the 90 days
-- before that order - helps identify suppliers whose performance is declining

WITH order_history AS (
    SELECT 
        po_current.order_id,
        po_current.order_date,
        po_current.supplier_id,
        -- Count historical orders from the same supplier in past 90 days
        COUNT(po_past.order_id) as historical_orders_90d,
        SUM(d_past.late_delivery) as historical_late_orders_90d,
        -- Calculate rolling late rate (only if there's sufficient history)
        CASE 
            WHEN COUNT(po_past.order_id) >= 3 THEN  -- Need at least 3 orders for meaningful rate
                ROUND(100.0 * SUM(d_past.late_delivery) / COUNT(po_past.order_id), 2)
            ELSE NULL  -- Not enough historical data
        END as supplier_90d_late_rate_pct
    FROM purchase_orders po_current
    -- Look back at the same supplier's orders in the past 90 days
    LEFT JOIN purchase_orders po_past ON po_current.supplier_id = po_past.supplier_id
        AND po_past.order_date >= date(po_current.order_date, '-90 days')
        AND po_past.order_date < po_current.order_date  -- Must be strictly before current order
    LEFT JOIN deliveries d_past ON po_past.order_id = d_past.order_id
        AND d_past.cancelled = 0  -- Only count completed deliveries
    WHERE po_current.order_date >= '2025-04-01' 
        AND po_current.order_date <= '2025-06-30'
    GROUP BY po_current.order_id, po_current.order_date, po_current.supplier_id
)
SELECT 
    order_id,
    order_date,
    supplier_id,
    historical_orders_90d,
    historical_late_orders_90d,
    supplier_90d_late_rate_pct,
    -- Add interpretation for business users
    CASE 
        WHEN supplier_90d_late_rate_pct IS NULL THEN 'INSUFFICIENT_HISTORY'
        WHEN supplier_90d_late_rate_pct = 0 THEN 'PERFECT_RECORD'
        WHEN supplier_90d_late_rate_pct <= 10 THEN 'EXCELLENT'
        WHEN supplier_90d_late_rate_pct <= 25 THEN 'GOOD'
        WHEN supplier_90d_late_rate_pct <= 50 THEN 'CONCERNING'
        ELSE 'POOR_PERFORMER'
    END as performance_category
FROM order_history
ORDER BY order_date, order_id;

-- =============================================================================
-- QUERY 4: Price Window Overlap Detection
-- =============================================================================
-- Finds cases where a supplier has overlapping price periods for the same product
-- This could indicate pricing errors or contract management issues

WITH clean_price_data AS (
    -- First, clean the data and add row numbers for comparison
    SELECT 
        supplier_id,
        sku,
        valid_from,
        valid_to,
        price_per_uom,
        currency,
        min_qty,
        ROW_NUMBER() OVER (PARTITION BY supplier_id, sku ORDER BY valid_from, valid_to) as price_sequence
    FROM price_lists
    WHERE valid_from IS NOT NULL 
        AND valid_to IS NOT NULL
        AND date(valid_from) <= date(valid_to)  -- Ensure valid date ranges
),
overlapping_periods AS (
    SELECT 
        p1.supplier_id,
        p1.sku,
        p1.valid_from as period1_start,
        p1.valid_to as period1_end,
        p1.price_per_uom as price1,
        p1.currency as currency1,
        p1.min_qty as min_qty1,
        p2.valid_from as period2_start,
        p2.valid_to as period2_end,
        p2.price_per_uom as price2,
        p2.currency as currency2,
        p2.min_qty as min_qty2,
        -- Calculate how many days the periods overlap
        CAST(
            julianday(MIN(date(p1.valid_to), date(p2.valid_to))) - 
            julianday(MAX(date(p1.valid_from), date(p2.valid_from))) + 1
            AS INTEGER
        ) as overlap_days
    FROM clean_price_data p1
    JOIN clean_price_data p2 ON p1.supplier_id = p2.supplier_id 
        AND p1.sku = p2.sku
        AND p1.price_sequence < p2.price_sequence  -- Compare each pair only once
    WHERE 
        -- Check if periods actually overlap
        date(p1.valid_from) <= date(p2.valid_to) 
        AND date(p1.valid_to) >= date(p2.valid_from)
)
SELECT 
    supplier_id,
    sku,
    period1_start,
    period1_end,
    price1,
    currency1,
    period2_start,
    period2_end,
    price2,
    currency2,
    overlap_days,
    -- Categorize the severity of overlap
    CASE 
        WHEN overlap_days > 30 THEN 'MAJOR_OVERLAP'
        WHEN overlap_days > 7 THEN 'MODERATE_OVERLAP'
        ELSE 'MINOR_OVERLAP'
    END as overlap_severity,
    -- Flag if prices are different during overlap (potential conflict)
    CASE 
        WHEN price1 != price2 OR currency1 != currency2 THEN 'PRICE_CONFLICT'
        ELSE 'SAME_PRICE'
    END as pricing_issue
FROM overlapping_periods
ORDER BY overlap_days DESC, supplier_id, sku;

-- =============================================================================
-- QUERY 5: Order Pricing with EUR Normalization
-- =============================================================================
-- Matches orders with valid prices and converts everything to EUR for analysis
-- Uses flexible matching to maximize the number of orders we can price

WITH flexible_price_matching AS (
    SELECT 
        po.order_id,
        po.order_date,
        po.supplier_id,
        po.sku,
        po.qty as quantity,
        pl.price_per_uom,
        pl.currency,
        pl.min_qty,
        pl.valid_from,
        pl.valid_to,
        -- Prioritize exact matches, then fall back to flexible matches
        CASE 
            WHEN po.order_date >= pl.valid_from 
                AND po.order_date <= pl.valid_to 
                AND po.qty >= pl.min_qty THEN 1  -- Perfect match
            WHEN po.order_date >= pl.valid_from 
                AND po.order_date <= pl.valid_to THEN 2  -- Date match, quantity flexible
            ELSE 3  -- Closest available price
        END as match_quality,
        ROW_NUMBER() OVER (
            PARTITION BY po.order_id 
            ORDER BY 
                CASE 
                    WHEN po.order_date >= pl.valid_from 
                        AND po.order_date <= pl.valid_to 
                        AND po.qty >= pl.min_qty THEN 1
                    WHEN po.order_date >= pl.valid_from 
                        AND po.order_date <= pl.valid_to THEN 2
                    ELSE 3
                END,
                pl.min_qty ASC  -- Prefer lower minimum quantities
        ) as match_rank
    FROM purchase_orders po
    LEFT JOIN price_lists pl ON po.supplier_id = pl.supplier_id AND po.sku = pl.sku
    WHERE po.order_date >= '2025-04-01' 
        AND po.order_date <= '2025-06-30'
),
best_price_matches AS (
    SELECT * 
    FROM flexible_price_matching 
    WHERE match_rank = 1  -- Take the best match for each order
)
SELECT 
    order_id,
    order_date,
    supplier_id,
    sku,
    quantity,
    price_per_uom as original_price,
    currency as original_currency,
    -- Convert all prices to EUR using the specified exchange rate
    CASE 
        WHEN currency = 'EUR' THEN price_per_uom
        WHEN currency = 'USD' THEN ROUND(price_per_uom * 0.92, 4)  -- USD to EUR = 0.92
        WHEN price_per_uom IS NOT NULL THEN price_per_uom  -- Other currencies as-is
        ELSE NULL
    END as unit_price_eur,
    -- Calculate total order value in EUR
    CASE 
        WHEN currency = 'EUR' THEN ROUND(price_per_uom * quantity, 2)
        WHEN currency = 'USD' THEN ROUND(price_per_uom * 0.92 * quantity, 2)
        WHEN price_per_uom IS NOT NULL THEN ROUND(price_per_uom * quantity, 2)
        ELSE NULL
    END as order_value_eur,
    -- Explain what kind of price match we found
    CASE 
        WHEN price_per_uom IS NULL THEN 'NO_PRICE_AVAILABLE'
        WHEN match_quality = 1 THEN 'EXACT_MATCH'
        WHEN match_quality = 2 THEN 'DATE_MATCH_QTY_FLEXIBLE'
        ELSE 'CLOSEST_AVAILABLE'
    END as pricing_method
FROM best_price_matches
ORDER BY order_date, order_id;

-- =============================================================================
-- QUERY 6: Price Anomaly Detection Using Statistical Methods
-- =============================================================================
-- Identifies unusually high or low prices that might indicate data entry errors
-- or supplier pricing issues requiring investigation

WITH price_normalization AS (
    -- Convert all prices to EUR and calculate log prices for statistical analysis
    SELECT 
        supplier_id,
        sku,
        price_per_uom as original_price,
        currency,
        valid_from,
        -- Normalize all prices to EUR
        CASE 
            WHEN currency = 'EUR' THEN price_per_uom
            WHEN currency = 'USD' THEN price_per_uom * 0.92
            ELSE price_per_uom
        END as price_eur,
        -- Use natural log for better statistical properties (handles right-skewed price distributions)
        CASE 
            WHEN price_per_uom > 0 THEN 
                LN(CASE 
                    WHEN currency = 'EUR' THEN price_per_uom
                    WHEN currency = 'USD' THEN price_per_uom * 0.92
                    ELSE price_per_uom
                END)
            ELSE NULL
        END as ln_price_eur
    FROM price_lists
    WHERE price_per_uom > 0  -- Only analyze positive prices
),
price_statistics AS (
    -- Calculate mean and standard deviation for each supplier-product combination
    SELECT 
        supplier_id,
        sku,
        COUNT(*) as price_points,
        AVG(ln_price_eur) as mean_ln_price,
        -- SQLite doesn't have built-in STDDEV, so calculate manually
        SQRT(
            AVG((ln_price_eur - (
                SELECT AVG(ln_price_eur) 
                FROM price_normalization p2 
                WHERE p2.supplier_id = p1.supplier_id AND p2.sku = p1.sku
            )) * (ln_price_eur - (
                SELECT AVG(ln_price_eur) 
                FROM price_normalization p2 
                WHERE p2.supplier_id = p1.supplier_id AND p2.sku = p1.sku
            )))
        ) as std_ln_price
    FROM price_normalization p1
    GROUP BY supplier_id, sku
    HAVING COUNT(*) >= 3  -- Need at least 3 price points for meaningful statistics
),
anomaly_detection AS (
    SELECT 
        pn.supplier_id,
        pn.sku,
        pn.original_price,
        pn.currency,
        pn.price_eur,
        pn.valid_from,
        pn.ln_price_eur,
        ps.mean_ln_price,
        ps.std_ln_price,
        ps.price_points,
        -- Calculate z-score (how many standard deviations from mean)
        CASE 
            WHEN ps.std_ln_price > 0 THEN 
                (pn.ln_price_eur - ps.mean_ln_price) / ps.std_ln_price
            ELSE 0
        END as z_score,
        ABS(CASE 
            WHEN ps.std_ln_price > 0 THEN 
                (pn.ln_price_eur - ps.mean_ln_price) / ps.std_ln_price
            ELSE 0
        END) as abs_z_score
    FROM price_normalization pn
    JOIN price_statistics ps ON pn.supplier_id = ps.supplier_id AND pn.sku = ps.sku
    WHERE ps.std_ln_price > 0  -- Only where we can calculate meaningful z-scores
)
SELECT 
    supplier_id,
    sku,
    original_price,
    currency,
    price_eur,
    valid_from,
    ROUND(z_score, 3) as z_score,
    ROUND(abs_z_score, 3) as absolute_z_score,
    price_points as historical_prices_count,
    -- Classify anomaly severity using standard statistical thresholds
    CASE 
        WHEN abs_z_score > 3 THEN 'EXTREME_OUTLIER'     -- 99.7% confidence
        WHEN abs_z_score > 2.5 THEN 'STRONG_OUTLIER'   -- 99% confidence
        WHEN abs_z_score > 2 THEN 'MODERATE_OUTLIER'   -- 95% confidence
        ELSE 'MILD_OUTLIER'
    END as anomaly_severity,
    -- Indicate direction of anomaly
    CASE 
        WHEN z_score > 0 THEN 'UNUSUALLY_HIGH'
        ELSE 'UNUSUALLY_LOW'
    END as price_direction
FROM anomaly_detection
ORDER BY abs_z_score DESC
LIMIT 10;

-- =============================================================================
-- QUERY 7: Shipping Performance Analysis by Distance and Terms
-- =============================================================================
-- Analyzes how delivery performance varies by shipping terms (incoterms) and 
-- distance ranges - helps optimize logistics strategies

WITH delivery_analysis AS (
    SELECT 
        po.order_id,
        po.incoterm,
        po.distance_km,
        -- Create meaningful distance categories for business analysis
        CASE 
            WHEN po.distance_km IS NULL THEN 'UNKNOWN_DISTANCE'
            WHEN po.distance_km <= 100 THEN 'LOCAL (≤100km)'
            WHEN po.distance_km <= 500 THEN 'REGIONAL (100-500km)'
            WHEN po.distance_km <= 1500 THEN 'NATIONAL (500-1500km)'
            WHEN po.distance_km <= 3000 THEN 'CONTINENTAL (1500-3000km)'
            ELSE 'INTERNATIONAL (>3000km)'
        END as distance_category,
        d.delay_days,
        d.late_delivery,
        d.partial_delivery
    FROM purchase_orders po
    JOIN deliveries d ON po.order_id = d.order_id
    WHERE po.order_date >= '2025-04-01' 
        AND po.order_date <= '2025-06-30'
        AND d.cancelled = 0
        AND po.incoterm IS NOT NULL
)
SELECT 
    incoterm as shipping_terms,
    distance_category,
    COUNT(*) as total_shipments,
    -- Performance metrics
    ROUND(AVG(delay_days), 2) as avg_delay_days,
    ROUND(MIN(delay_days), 2) as best_delivery_days,
    ROUND(MAX(delay_days), 2) as worst_delay_days,
    COUNT(CASE WHEN late_delivery = 1 THEN 1 END) as late_deliveries,
    ROUND(100.0 * COUNT(CASE WHEN late_delivery = 1 THEN 1 END) / COUNT(*), 2) as late_rate_pct,
    COUNT(CASE WHEN partial_delivery = 1 THEN 1 END) as partial_deliveries,
    ROUND(100.0 * COUNT(CASE WHEN partial_delivery = 1 THEN 1 END) / COUNT(*), 2) as partial_rate_pct
FROM delivery_analysis
WHERE distance_category != 'UNKNOWN_DISTANCE'  -- Focus on shipments with known distances
GROUP BY incoterm, distance_category
HAVING COUNT(*) >= 5  -- Only include combinations with sufficient sample size
ORDER BY 
    incoterm,
    CASE distance_category
        WHEN 'LOCAL (≤100km)' THEN 1
        WHEN 'REGIONAL (100-500km)' THEN 2
        WHEN 'NATIONAL (500-1500km)' THEN 3
        WHEN 'CONTINENTAL (1500-3000km)' THEN 4
        WHEN 'INTERNATIONAL (>3000km)' THEN 5
    END;

-- =============================================================================
-- BONUS QUERY 8: Risk-Based Analysis (For Use with Predictions)
-- =============================================================================
-- This query template can be used if you have machine learning predictions
-- Uncomment and modify the table name if you have a predictions file loaded


WITH risk_segmentation AS (
    SELECT 
        p.order_id,
        p.p_late as predicted_late_probability,
        po.order_date,
        po.supplier_id,
        po.ship_mode,
        -- Create risk buckets for operational decision-making
        CASE 
            WHEN p.p_late >= 0.7 THEN 'HIGH_RISK'
            WHEN p.p_late >= 0.3 THEN 'MEDIUM_RISK'
            ELSE 'LOW_RISK'
        END as risk_category,
        -- Also create capacity-based buckets (top 10% = high risk)
        CASE 
            WHEN p.p_late >= (
                SELECT p_late 
                FROM predictions 
                ORDER BY p_late DESC 
                LIMIT 1 OFFSET (SELECT COUNT(*) * 0.1 FROM predictions)
            ) THEN 'TOP_10_PCT_RISK'
            ELSE 'LOWER_90_PCT_RISK'
        END as capacity_bucket,
        d.late_delivery as actual_outcome
    FROM predictions p
    JOIN purchase_orders po ON p.order_id = po.order_id
    JOIN deliveries d ON p.order_id = d.order_id
    WHERE po.order_date >= '2025-04-01' 
        AND po.order_date <= '2025-06-30'
        AND d.cancelled = 0
)
SELECT 
    'RISK_BASED_ANALYSIS' as analysis_type,
    risk_category,
    capacity_bucket,
    COUNT(*) as total_orders,
    SUM(actual_outcome) as actual_late_orders,
    ROUND(100.0 * SUM(actual_outcome) / COUNT(*), 2) as actual_late_rate_pct,
    ROUND(AVG(predicted_late_probability), 4) as avg_predicted_probability,
    ROUND(MIN(predicted_late_probability), 4) as min_predicted_probability,
    ROUND(MAX(predicted_late_probability), 4) as max_predicted_probability
FROM risk_segmentation
GROUP BY risk_category, capacity_bucket
ORDER BY risk_category, capacity_bucket;


-- =============================================================================
-- SUMMARY DASHBOARD: Key Business Metrics
-- =============================================================================
-- Executive summary of key performance indicators for the validation period

SELECT 
    '=== PROCUREMENT PERFORMANCE SUMMARY ===' as dashboard_section,
    COUNT(DISTINCT po.order_id) as total_orders,
    COUNT(DISTINCT po.supplier_id) as active_suppliers,
    COUNT(DISTINCT po.sku) as products_ordered,
    -- Delivery performance
    SUM(d.late_delivery) as late_deliveries,
    ROUND(100.0 * SUM(d.late_delivery) / COUNT(*), 2) as overall_late_rate_pct,
    ROUND(AVG(d.delay_days), 2) as avg_delay_days,
    -- Order completion
    COUNT(CASE WHEN d.cancelled = 1 THEN 1 END) as cancelled_orders,
    COUNT(CASE WHEN d.partial_delivery = 1 THEN 1 END) as partial_deliveries,
    ROUND(100.0 * COUNT(CASE WHEN d.cancelled = 1 THEN 1 END) / COUNT(*), 2) as cancellation_rate_pct,
    -- Operational insights
    (SELECT COUNT(DISTINCT ship_mode) FROM purchase_orders 
     WHERE order_date >= '2025-04-01' AND order_date <= '2025-06-30') as shipping_methods_used,
    (SELECT COUNT(DISTINCT incoterm) FROM purchase_orders 
     WHERE order_date >= '2025-04-01' AND order_date <= '2025-06-30') as incoterms_used
FROM purchase_orders po
JOIN deliveries d ON po.order_id = d.order_id
WHERE po.order_date >= '2025-04-01' 
    AND po.order_date <= '2025-06-30';

-- =============================================================================
-- END OF SQL EXERCISE
-- =============================================================================
-- These queries provide comprehensive insights into:
-- 1. Temporal delivery patterns and shipping method effectiveness
-- 2. Supplier performance ranking and reliability metrics  
-- 3. Historical performance trends for risk assessment
-- 4. Data quality issues in pricing systems
-- 5. Flexible pricing with currency normalization
-- 6. Statistical anomaly detection for pricing errors
-- 7. Logistics optimization opportunities by distance and terms
-- 8. Executive dashboard for strategic decision-making
-- 
-- Each query is designed to provide actionable business insights while
-- maintaining data integrity and handling edge cases appropriately.
-- =============================================================================