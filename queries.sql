-- ============================================
-- Olist Brazilian E-Commerce SQL Analysis
-- Author: Dana Dobrosavljevic
-- ============================================

USE olist;

-- ============================================
-- DATA PREPARATION
-- ============================================

-- Combine products with English category names to optimise join performance
CREATE TABLE products_with_category AS
SELECT 
    p.product_id,
    p.product_category_name,
    t.product_category_name_english
FROM olist_products_dataset p
LEFT JOIN product_category_name_translation t
    ON p.product_category_name = t.product_category_name;

-- Remove non-delivered orders (cancelled, unavailable, processing)
-- 2,963 rows removed, leaving 96,478 delivered orders for analysis
SET SQL_SAFE_UPDATES = 0;
DELETE FROM olist_orders_dataset 
WHERE order_status != 'delivered';

-- ============================================
-- QUERY 1: Monthly Revenue Trend (2017-2018)
-- Business Question: How does revenue trend over time and when does the platform peak?
-- ============================================
SELECT 
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS month,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue,
    COUNT(DISTINCT o.order_id) AS total_orders
FROM olist_orders_dataset o
JOIN olist_order_items_dataset oi 
    ON o.order_id = oi.order_id
WHERE YEAR(o.order_purchase_timestamp) IN (2017, 2018)
GROUP BY month
ORDER BY month;

-- ============================================
-- QUERY 2: Revenue by Product Category (Top 10)
-- Business Question: Which product categories drive the most revenue?
-- ============================================
SELECT 
    pc.product_category_name_english AS category,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    ROUND(AVG(oi.price), 2) AS avg_item_price
FROM olist_order_items_dataset oi
JOIN olist_orders_dataset o 
    ON oi.order_id = o.order_id
JOIN products_with_category pc 
    ON oi.product_id = pc.product_id
WHERE pc.product_category_name_english IS NOT NULL
GROUP BY category
ORDER BY total_revenue DESC
LIMIT 10;

-- ============================================
-- QUERY 2b: Most Ordered Categories (Top 10)
-- Business Question: Which categories drive the most order volume?
-- ============================================
SELECT 
    pc.product_category_name_english AS category,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    ROUND(AVG(oi.price), 2) AS avg_item_price
FROM olist_order_items_dataset oi
JOIN olist_orders_dataset o 
    ON oi.order_id = o.order_id
JOIN products_with_category pc 
    ON oi.product_id = pc.product_id
WHERE pc.product_category_name_english IS NOT NULL
GROUP BY category
ORDER BY total_orders DESC
LIMIT 10;

-- ============================================
-- QUERY 3: Payment Method Analysis
-- Business Question: How do payment methods affect order value?
-- ============================================
SELECT 
    payment_type,
    COUNT(DISTINCT order_id) AS total_orders,
    ROUND(SUM(payment_value), 2) AS total_revenue,
    ROUND(AVG(payment_value), 2) AS avg_order_value,
    ROUND(AVG(payment_installments), 2) AS avg_installments
FROM olist_order_payments_dataset
WHERE payment_type != 'not_defined'
GROUP BY payment_type
ORDER BY total_revenue DESC;

-- ============================================
-- QUERY 3b: Installment Payments vs Order Value
-- Business Question: Do more installments = higher spend?
-- ============================================
SELECT 
    payment_installments,
    COUNT(DISTINCT order_id) AS total_orders,
    ROUND(AVG(payment_value), 2) AS avg_order_value
FROM olist_order_payments_dataset
WHERE payment_type = 'credit_card'
GROUP BY payment_installments
ORDER BY payment_installments;

-- ============================================
-- QUERY 4: High Revenue Sellers with Poor Reviews
-- Business Question: Which sellers generate high revenue but pose a satisfaction risk?
-- ============================================
SELECT 
    oi.seller_id,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue,
    ROUND(AVG(r.review_score), 2) AS avg_review_score,
    ROUND(AVG(DATEDIFF(
        o.order_delivered_customer_date, 
        o.order_estimated_delivery_date
    )), 2) AS avg_days_late
FROM olist_order_items_dataset oi
JOIN olist_orders_dataset o ON oi.order_id = o.order_id
JOIN olist_order_reviews_dataset r ON oi.order_id = r.order_id
GROUP BY oi.seller_id
HAVING total_orders >= 50 AND avg_review_score < 3.5
ORDER BY total_revenue DESC
LIMIT 10;

-- ============================================
-- QUERY 5: Delivery Performance vs Review Score
-- Business Question: At what point does late delivery cause satisfaction to collapse?
-- ============================================
SELECT 
    CASE 
        WHEN DATEDIFF(o.order_delivered_customer_date, 
             o.order_estimated_delivery_date) <= 0 THEN 'Early or On Time'
        WHEN DATEDIFF(o.order_delivered_customer_date, 
             o.order_estimated_delivery_date) BETWEEN 1 AND 7 THEN '1-7 Days Late'
        WHEN DATEDIFF(o.order_delivered_customer_date, 
             o.order_estimated_delivery_date) BETWEEN 8 AND 14 THEN '8-14 Days Late'
        ELSE '14+ Days Late'
    END AS delivery_status,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(AVG(r.review_score), 2) AS avg_review_score
FROM olist_orders_dataset o
JOIN olist_order_reviews_dataset r ON o.order_id = r.order_id
GROUP BY delivery_status
ORDER BY avg_review_score DESC;

-- ============================================
-- QUERY 6: Financial Impact of Late Deliveries
-- Business Question: How much revenue is at risk from poor delivery performance?
-- ============================================
SELECT 
    CASE 
        WHEN DATEDIFF(o.order_delivered_customer_date, 
             o.order_estimated_delivery_date) <= 0 THEN 'Early or On Time'
        WHEN DATEDIFF(o.order_delivered_customer_date, 
             o.order_estimated_delivery_date) BETWEEN 1 AND 7 THEN '1-7 Days Late'
        WHEN DATEDIFF(o.order_delivered_customer_date, 
             o.order_estimated_delivery_date) BETWEEN 8 AND 14 THEN '8-14 Days Late'
        ELSE '14+ Days Late'
    END AS delivery_status,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue,
    ROUND(AVG(oi.price + oi.freight_value), 2) AS avg_order_value,
    ROUND(AVG(r.review_score), 2) AS avg_review_score
FROM olist_orders_dataset o
JOIN olist_order_items_dataset oi ON o.order_id = oi.order_id
JOIN olist_order_reviews_dataset r ON o.order_id = r.order_id
GROUP BY delivery_status
ORDER BY total_revenue DESC;
