-- Run this in ADM user
-- TEST A: SCD Type 2 Trigger
-- Deactivate a customer to see if the warehouse creates a new version.
UPDATE adm.Customer SET Status = 'Inactive' WHERE CustomerID = 'C002'; 

-- TEST B: Dirty Sales Data 
-- Create an order with an invalid type, negative quantity, and negative price[cite: 35].
INSERT INTO adm.Orders (OrderNo, CustomerID, BranchID, OrderDateTime, OrderType, TotalAmount) 
VALUES ('ODIRT1', 'C001', 'B001', SYSDATE, 'Telephone', 100.00); 

INSERT INTO adm.OrderDetails (OrderNo, ItemID, Quantity, UnitPrice, Subtotal) 
VALUES ('ODIRT1', 'I001', -5, -10.00, 0);

-- TEST C: Mutable Delivery (Pending state with negative charge)
-- Insert a delivery with no date, a 'Pending' status, and a negative charge[cite: 35].
INSERT INTO adm.Delivery (DeliveryID, OrderNo, DeliveryCompanyID, AddressID, DeliveryDate, Status, DeliveryCharge) 
VALUES ('DDIRT1', 'ODIRT1', 'DC01', 'A001', NULL, 'Pending', -15.50); 

COMMIT;