-- This script creates a stored procedure to retrieve customer information based on CustomerId.
-- Create stored procedure to get customer info
CREATE OR ALTER PROCEDURE usp_GetCustomer @CustomerId INT
AS
BEGIN
    SELECT * FROM Customers WHERE CustomerId = @CustomerId;
END;