-- 1. EMPTY THE FACT TABLES FIRST
DELETE FROM sales_fact;
DELETE FROM return_fact;
DELETE FROM delivery_fact;
DELETE FROM point_fact;

-- 2. EMPTY THE DIMENSION TABLES
DELETE FROM item_dim;
DELETE FROM customer_dim;
DELETE FROM address_dim;
DELETE FROM branch_dim;
DELETE FROM delivery_company_dim;
DELETE FROM promotion_dim;
DELETE FROM return_reason_dim;
DELETE FROM date_dim;

COMMIT;
DBMS_OUTPUT.PUT_LINE('All tables cleared and ready for initial load.');