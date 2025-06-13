-- Create stored procedure to add a customer
CREATE OR ALTER PROCEDURE usp_AddCustomer @Name NVARCHAR(100), @Email NVARCHAR(100)
AS
BEGIN
    INSERT INTO Customers (Name, Email) VALUES (@Name, @Email);
END;