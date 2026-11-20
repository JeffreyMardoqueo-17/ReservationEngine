USE ReservationEngineDb;
GO

CREATE OR ALTER PROCEDURE dbo.usp_CreateSlot
    @Name       NVARCHAR(150),
    @TotalSpots INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @NewId UNIQUEIDENTIFIER = NEWID();

    INSERT INTO dbo.Slots (Id, Name, TotalSpots, AvailableSpots, CreatedAt, UpdatedAt)
    VALUES (@NewId, @Name, @TotalSpots, @TotalSpots, @Now, @Now);

    SELECT Id, Name, TotalSpots, AvailableSpots, CreatedAt, UpdatedAt
    FROM dbo.Slots
    WHERE Id = @NewId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_GetSlotById
    @Id UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Name, TotalSpots, AvailableSpots, CreatedAt, UpdatedAt
    FROM dbo.Slots
    WHERE Id = @Id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_GetAllSlots
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Name, TotalSpots, AvailableSpots, CreatedAt, UpdatedAt
    FROM dbo.Slots
    ORDER BY CreatedAt DESC;
END;
GO