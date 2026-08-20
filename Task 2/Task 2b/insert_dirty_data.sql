-- Run this in ADM user
-- TEST A: SCD Type 2 Trigger
-- Deactivate a customer to see if the warehouse creates a new version.
UPDATE adm.Customer SET Status = 'Inactive' WHERE CustomerID = 'C0187'; 

-- TEST B: Dirty Sales Data 
-- Create an order with an invalid type, negative quantity, and negative price[cite: 35].
INSERT INTO adm.Orders (OrderNo, CustomerID, BranchID, OrderDateTime, OrderType, TotalAmount) 
VALUES ('ORD01154', 'C0188', 'BR001', SYSDATE, 'Walk-in', 100.00); 

INSERT INTO adm.OrderDetails (OrderNo, ItemID, Quantity, UnitPrice, Subtotal) 
VALUES ('ORD01154', 'I0025', -5, -10.00, 0);

-- TEST C: Mutable Delivery (Pending state with negative charge)
-- Insert a delivery with no date, a 'Pending' status, and a negative charge[cite: 35].
INSERT INTO adm.Delivery (DeliveryID, OrderNo, DeliveryCompanyID, AddressID, DeliveryDate, Status, DeliveryCharge) 
VALUES ('DLV00267', 'ORD00863', 'DC04', 'A0183', NULL, 'Pending', -15.50); 

COMMIT;