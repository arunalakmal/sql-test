-- Validate that data and stored procs behave as expected
EXEC usp_GetCustomer @CustomerId = 1;
EXEC usp_AddCustomer @Name = 'Charlie Brown', @Email = 'charlie@example.com';
SELECT * FROM Customers WHERE Email = 'charlie@example.com';