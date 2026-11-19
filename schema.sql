/* ============================================================================
   Archivo: 01_schema.sql
   Motor:   SQL Server (T-SQL)
   Propósito: Definir el modelo relacional del Motor de Reservas con
              restricciones de integridad (CHECK, UNIQUE, FK), índices para
              concurrencia/expiración y tablas de auditoría e idempotencia.
   ============================================================================ */

IF DB_ID(N'ReservationEngineDb') IS NULL
BEGIN
    CREATE DATABASE ReservationEngineDb;
END
GO

USE ReservationEngineDb;
GO

/* ----------------------------------------------------------------------------
   1. dbo.Slots
      Representa un recurso, evento o bloque con cupos limitados.
      Invariante: AvailableSpots nunca puede ser < 0 ni superar a TotalSpots.
   ---------------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.Slots', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Slots
    (
        Id             UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Slots_Id DEFAULT NEWSEQUENTIALID(),
        Name           NVARCHAR(150)    NOT NULL,
        TotalSpots     INT              NOT NULL,
        AvailableSpots INT              NOT NULL,
        CreatedAt      DATETIME2(3)     NOT NULL CONSTRAINT DF_Slots_CreatedAt DEFAULT SYSUTCDATETIME(),
        UpdatedAt      DATETIME2(3)     NOT NULL CONSTRAINT DF_Slots_UpdatedAt DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_Slots PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT CK_Slots_TotalSpots CHECK (TotalSpots > 0),
        CONSTRAINT CK_Slots_AvailableSpots CHECK (AvailableSpots >= 0 AND AvailableSpots <= TotalSpots)
    );
END
GO

-- Evita duplicar exactamente el mismo nombre de cupo/recurso
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_Slots_Name' AND object_id = OBJECT_ID(N'dbo.Slots'))
BEGIN
    CREATE UNIQUE INDEX UQ_Slots_Name ON dbo.Slots (Name);
END
GO

/* ----------------------------------------------------------------------------
   2. dbo.Reservations
      Representa una reserva asociada a un Slot.
      Estados (ReservationStatus):
        1 = Pending   (cupo apartado temporalmente hasta ExpiresAt)
        2 = Confirmed (reserva confirmada; mantiene el cupo ocupado)
        3 = Cancelled (cancelada manualmente; devuelve cupo si estaba activa)
        4 = Expired   (venció su TTL sin confirmar; el worker devuelve el cupo)
   ---------------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.Reservations', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Reservations
    (
        Id          UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Reservations_Id DEFAULT NEWSEQUENTIALID(),
        SlotId      UNIQUEIDENTIFIER NOT NULL,
        CustomerRef NVARCHAR(100)    NOT NULL,
        SpotsCount  INT              NOT NULL,
        Status      TINYINT          NOT NULL,
        ExpiresAt   DATETIME2(3)     NOT NULL,
        CreatedAt   DATETIME2(3)     NOT NULL CONSTRAINT DF_Reservations_CreatedAt DEFAULT SYSUTCDATETIME(),
        UpdatedAt   DATETIME2(3)     NOT NULL CONSTRAINT DF_Reservations_UpdatedAt DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_Reservations PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT FK_Reservations_Slots FOREIGN KEY (SlotId) REFERENCES dbo.Slots (Id),
        CONSTRAINT CK_Reservations_SpotsCount CHECK (SpotsCount > 0),
        CONSTRAINT CK_Reservations_Status CHECK (Status IN (1, 2, 3, 4))
    );
END
GO

-- Índice compuesto para consultar reservas de un cliente o por slot rápidamente
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Reservations_SlotId_Status' AND object_id = OBJECT_ID(N'dbo.Reservations'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_Reservations_SlotId_Status
    ON dbo.Reservations (SlotId, Status)
    INCLUDE (CustomerRef, SpotsCount, ExpiresAt, CreatedAt);
END
GO

-- Índice filtrado crítico para el BackgroundService: busca solo reservas Pending (Status = 1)
-- ordenadas por fecha de expiración para liberar cupos vencidos sin escanear toda la tabla.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Reservations_Pending_ExpiresAt' AND object_id = OBJECT_ID(N'dbo.Reservations'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_Reservations_Pending_ExpiresAt
    ON dbo.Reservations (ExpiresAt ASC)
    INCLUDE (SlotId, SpotsCount)
    WHERE Status = 1;
END
GO

/* ----------------------------------------------------------------------------
   3. dbo.ReservationAuditLogs
      Bitácora inmutable de cada transición de estado de una reserva.
      Permite auditar qué pasó, cuándo y por qué motivo.
   ---------------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.ReservationAuditLogs', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ReservationAuditLogs
    (
        Id             BIGINT           IDENTITY(1,1) NOT NULL,
        ReservationId  UNIQUEIDENTIFIER NOT NULL,
        PreviousStatus TINYINT          NULL,
        NewStatus      TINYINT          NOT NULL,
        Reason         NVARCHAR(250)    NOT NULL,
        ChangedAt      DATETIME2(3)     NOT NULL CONSTRAINT DF_AuditLogs_ChangedAt DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_ReservationAuditLogs PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT FK_AuditLogs_Reservations FOREIGN KEY (ReservationId) REFERENCES dbo.Reservations (Id),
        CONSTRAINT CK_AuditLogs_PreviousStatus CHECK (PreviousStatus IS NULL OR PreviousStatus IN (1, 2, 3, 4)),
        CONSTRAINT CK_AuditLogs_NewStatus CHECK (NewStatus IN (1, 2, 3, 4))
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_AuditLogs_ReservationId_ChangedAt' AND object_id = OBJECT_ID(N'dbo.ReservationAuditLogs'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_AuditLogs_ReservationId_ChangedAt
    ON dbo.ReservationAuditLogs (ReservationId, ChangedAt ASC);
END
GO

/* ----------------------------------------------------------------------------
   4. dbo.IdempotencyKeys
      Garantiza que reintentos de red con el mismo Idempotency-Key no dupliquen
      reservas ni descuenten cupos más de una vez.
      ProcessingStatus:
        1 = InProgress (en ejecución)
        2 = Completed  (finalizada; ResponseStatusCode y ResponseBody listos)
   ---------------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.IdempotencyKeys', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.IdempotencyKeys
    (
        IdempotencyKey   NVARCHAR(100) NOT NULL,
        RequestHash      CHAR(64)      NOT NULL, -- SHA-256 en hexadecimal del request canónico
        ProcessingStatus TINYINT       NOT NULL,
        HttpStatusCode   INT           NULL,
        ResponseBody     NVARCHAR(MAX) NULL,
        CreatedAt        DATETIME2(3)  NOT NULL CONSTRAINT DF_IdempotencyKeys_CreatedAt DEFAULT SYSUTCDATETIME(),
        ExpiresAt        DATETIME2(3)  NOT NULL,

        CONSTRAINT PK_IdempotencyKeys PRIMARY KEY CLUSTERED (IdempotencyKey),
        CONSTRAINT CK_IdempotencyKeys_Status CHECK (ProcessingStatus IN (1, 2))
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_IdempotencyKeys_ExpiresAt' AND object_id = OBJECT_ID(N'dbo.IdempotencyKeys'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_IdempotencyKeys_ExpiresAt
    ON dbo.IdempotencyKeys (ExpiresAt ASC);
END
GO