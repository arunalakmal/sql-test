-- Create schema and insert test data
CREATE TABLE Customers (
    CustomerId INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100),
    Email NVARCHAR(100)
);

INSERT INTO Customers (Name, Email) VALUES ('Alice Smith', 'alice@example.com');
INSERT INTO Customers (Name, Email) VALUES ('Bob Jones', 'bob@example.com');