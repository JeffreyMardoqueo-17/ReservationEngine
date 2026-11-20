/* ============================================================================
   Archivo: 03_seed.sql
   Motor:   SQL Server (T-SQL)
   Propósito: Poblar datos iniciales de prueba de forma idempotente (seguro de
              ejecutar más de una vez sin duplicar registros ni romper
              restricciones) para validar:
              - Prueba de concurrencia (pocos cupos vs. muchas peticiones)
              - Estados de reserva (Pending, Confirmed, Cancelled, Expired)
              - Historial de auditoría (dbo.ReservationAuditLogs)
              - Liberación automática de reservas vencidas
   ============================================================================ */

USE ReservationEngineDb;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @Now DATETIME2(3) = SYSUTCDATETIME();

    -- GUIDs fijos para facilitar pruebas manuales en Postman/Swagger/SSMS
    DECLARE @SlotConcurrencyId UNIQUEIDENTIFIER = '11111111-1111-1111-1111-111111111101'; -- 5 cupos (ideal para prueba de 50 requests)
    DECLARE @SlotWorkshopId    UNIQUEIDENTIFIER = '11111111-1111-1111-1111-111111111102'; -- 20 cupos con reservas mixtas
    DECLARE @SlotSoldOutId     UNIQUEIDENTIFIER = '11111111-1111-1111-1111-111111111103'; -- 0 cupos disponibles (prueba directa de 409 Conflict)

    DECLARE @ResConfirmedId    UNIQUEIDENTIFIER = '22222222-2222-2222-2222-222222222201';
    DECLARE @ResPendingActiveId  UNIQUEIDENTIFIER = '22222222-2222-2222-2222-222222222202';
    DECLARE @ResExpiredDueId     UNIQUEIDENTIFIER = '22222222-2222-2222-2222-222222222203'; -- Ya vencida: lista para expirar
    DECLARE @ResCancelledId    UNIQUEIDENTIFIER = '22222222-2222-2222-2222-222222222204';

    /* ------------------------------------------------------------------------
       1. Slots iniciales
          Nota sobre @SlotWorkshopId:
          TotalSpots = 20.
          Reservas que ocupan cupo actualmente:
            - @ResConfirmedId   (3 cupos, Confirmed = 2)
            - @ResPendingActive (2 cupos, Pending = 1, aún vigente)
            - @ResExpiredDueId  (4 cupos, Pending = 1, ya vencida -> cuando expire, devolverá 4 cupos)
          (@ResCancelledId tuvo 2 cupos, ya cancelados y devueltos previamente)
          Cupos disponibles actuales = 20 - 3 - 2 - 4 = 11.
          Cuando expire @ResExpiredDueId, pasará de 11 a 15 disponibles.
       ------------------------------------------------------------------------ */
    IF NOT EXISTS (SELECT 1 FROM dbo.Slots WHERE Id = @SlotConcurrencyId)
    BEGIN
        INSERT INTO dbo.Slots (Id, Name, TotalSpots, AvailableSpots, CreatedAt, UpdatedAt)
        VALUES (@SlotConcurrencyId, N'Flash Drop - 5 Spots Concurrency Test', 5, 5, @Now, @Now);
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.Slots WHERE Id = @SlotWorkshopId)
    BEGIN
        INSERT INTO dbo.Slots (Id, Name, TotalSpots, AvailableSpots, CreatedAt, UpdatedAt)
        VALUES (@SlotWorkshopId, N'Backend Architecture Session - Mixed States', 20, 11, @Now, @Now);
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.Slots WHERE Id = @SlotSoldOutId)
    BEGIN
        INSERT INTO dbo.Slots (Id, Name, TotalSpots, AvailableSpots, CreatedAt, UpdatedAt)
        VALUES (@SlotSoldOutId, N'Sold Out Event - Zero Available Spots', 10, 0, @Now, @Now);
    END

    /* ------------------------------------------------------------------------
       2. Reservas de ejemplo en distintos estados
          Estados: 1 = Pending, 2 = Confirmed, 3 = Cancelled, 4 = Expired
       ------------------------------------------------------------------------ */

    -- Reserva 1: Confirmada (Status = 2)
    IF NOT EXISTS (SELECT 1 FROM dbo.Reservations WHERE Id = @ResConfirmedId)
    BEGIN
        INSERT INTO dbo.Reservations
            (Id, SlotId, CustomerRef, SpotsCount, Status, ExpiresAt, CreatedAt, UpdatedAt)
        VALUES
            (@ResConfirmedId, @SlotWorkshopId, N'CUST-001', 3, 2,
             DATEADD(MINUTE, 10, @Now), DATEADD(MINUTE, -15, @Now), DATEADD(MINUTE, -12, @Now));

        INSERT INTO dbo.ReservationAuditLogs (ReservationId, PreviousStatus, NewStatus, Reason, ChangedAt)
        VALUES
            (@ResConfirmedId, NULL, 1, N'Reservation created in Pending status', DATEADD(MINUTE, -15, @Now)),
            (@ResConfirmedId, 1,    2, N'Reservation confirmed by customer',     DATEADD(MINUTE, -12, @Now));
    END

    -- Reserva 2: Pendiente activa (Status = 1, vence en 5 minutos)
    IF NOT EXISTS (SELECT 1 FROM dbo.Reservations WHERE Id = @ResPendingActiveId)
    BEGIN
        INSERT INTO dbo.Reservations
            (Id, SlotId, CustomerRef, SpotsCount, Status, ExpiresAt, CreatedAt, UpdatedAt)
        VALUES
            (@ResPendingActiveId, @SlotWorkshopId, N'CUST-002', 2, 1,
             DATEADD(MINUTE, 5, @Now), DATEADD(MINUTE, -2, @Now), DATEADD(MINUTE, -2, @Now));

        INSERT INTO dbo.ReservationAuditLogs (ReservationId, PreviousStatus, NewStatus, Reason, ChangedAt)
        VALUES
            (@ResPendingActiveId, NULL, 1, N'Reservation created in Pending status', DATEADD(MINUTE, -2, @Now));
    END

    -- Reserva 3: Pendiente pero YA VENCIDA (Status = 1, ExpiresAt hace 3 minutos)
    -- Ideal para probar usp_ExpireOverdueReservations o el BackgroundService
    IF NOT EXISTS (SELECT 1 FROM dbo.Reservations WHERE Id = @ResExpiredDueId)
    BEGIN
        INSERT INTO dbo.Reservations
            (Id, SlotId, CustomerRef, SpotsCount, Status, ExpiresAt, CreatedAt, UpdatedAt)
        VALUES
            (@ResExpiredDueId, @SlotWorkshopId, N'CUST-003', 4, 1,
             DATEADD(MINUTE, -3, @Now), DATEADD(MINUTE, -10, @Now), DATEADD(MINUTE, -10, @Now));

        INSERT INTO dbo.ReservationAuditLogs (ReservationId, PreviousStatus, NewStatus, Reason, ChangedAt)
        VALUES
            (@ResExpiredDueId, NULL, 1, N'Reservation created in Pending status', DATEADD(MINUTE, -10, @Now));
    END

    -- Reserva 4: Cancelada previamente (Status = 3)
    IF NOT EXISTS (SELECT 1 FROM dbo.Reservations WHERE Id = @ResCancelledId)
    BEGIN
        INSERT INTO dbo.Reservations
            (Id, SlotId, CustomerRef, SpotsCount, Status, ExpiresAt, CreatedAt, UpdatedAt)
        VALUES
            (@ResCancelledId, @SlotWorkshopId, N'CUST-004', 2, 3,
             DATEADD(MINUTE, 5, @Now), DATEADD(MINUTE, -20, @Now), DATEADD(MINUTE, -18, @Now));

        INSERT INTO dbo.ReservationAuditLogs (ReservationId, PreviousStatus, NewStatus, Reason, ChangedAt)
        VALUES
            (@ResCancelledId, NULL, 1, N'Reservation created in Pending status', DATEADD(MINUTE, -20, @Now)),
            (@ResCancelledId, 1,    3, N'Cancelled by user before confirmation', DATEADD(MINUTE, -18, @Now));
    END

    /* ------------------------------------------------------------------------
       3. Clave de idempotencia de ejemplo ya completada
          Útil para probar un reintento inmediato (debe devolver 201/200 sin
          crear otra reserva ni descontar cupos extra)
       ------------------------------------------------------------------------ */
    IF NOT EXISTS (SELECT 1 FROM dbo.IdempotencyKeys WHERE IdempotencyKey = N'SEED-IDEMPOTENCY-KEY-001')
    BEGIN
        DECLARE @SampleBody NVARCHAR(MAX) = (
            SELECT
                @ResConfirmedId AS id,
                @SlotWorkshopId AS slotId,
                N'CUST-001'     AS customerRef,
                3               AS spotsCount,
                N'Confirmed'    AS status
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        INSERT INTO dbo.IdempotencyKeys
            (IdempotencyKey, RequestHash, ProcessingStatus, HttpStatusCode, ResponseBody, CreatedAt, ExpiresAt)
        VALUES
            (N'SEED-IDEMPOTENCY-KEY-001',
             REPLICATE(N'a', 64), -- Hash de ejemplo para seed; en requests reales será SHA-256 real
             2,
             201,
             @SampleBody,
             DATEADD(MINUTE, -15, @Now),
             DATEADD(HOUR, 24, @Now));
    END

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO