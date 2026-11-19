/* ============================================================================
   Archivo: 02_stored_procedures.sql
   Motor:   SQL Server (T-SQL)
   Propósito: Encapsular operaciones críticas con transacciones ACID, bloqueo a
              nivel de fila (UPDLOCK, ROWLOCK, READPAST), idempotencia y
              registro automático de auditoría.

   Convención de códigos de retorno (ResultCode):
     200 = Operación exitosa / repetición idempotente ya resuelta
     201 = Recurso creado
     400 = Parámetros inválidos
     404 = Recurso no encontrado
     409 = Conflicto de negocio / estado inválido / sin cupos disponibles
     422 = Misma Idempotency-Key reutilizada con un payload distinto
   ============================================================================ */

USE ReservationEngineDb;
GO

/* ----------------------------------------------------------------------------
   SP 1: dbo.usp_CreateReservation
   Crea una reserva en estado Pending (1) descontando cupos de forma atómica.
   - Si 50 peticiones compiten por los últimos 5 cupos, UPDLOCK + ROWLOCK en
     dbo.Slots serializa el acceso a esa fila específica sin bloquear la tabla.
   - Valida y registra la Idempotency-Key dentro de la misma transacción.
   ---------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_CreateReservation
    @IdempotencyKey NVARCHAR(100),
    @RequestHash    CHAR(64),
    @SlotId         UNIQUEIDENTIFIER,
    @CustomerRef    NVARCHAR(100),
    @SpotsCount     INT,
    @TtlMinutes     INT = 5
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON; -- Si ocurre un error grave en T-SQL, aborta y hace rollback limpio

    DECLARE @Now DATETIME2(3) = SYSUTCDATETIME();

    -- Validaciones defensivas de entrada
    IF @IdempotencyKey IS NULL OR LTRIM(RTRIM(@IdempotencyKey)) = N''
    BEGIN
        SELECT 400 AS ResultCode, CAST(NULL AS UNIQUEIDENTIFIER) AS ReservationId,
               CAST(NULL AS NVARCHAR(MAX)) AS ResponseBody, N'Idempotency-Key is required.' AS Message;
        RETURN;
    END

    IF @SpotsCount IS NULL OR @SpotsCount <= 0 OR @TtlMinutes IS NULL OR @TtlMinutes <= 0
    BEGIN
        SELECT 400 AS ResultCode, CAST(NULL AS UNIQUEIDENTIFIER) AS ReservationId,
               CAST(NULL AS NVARCHAR(MAX)) AS ResponseBody, N'SpotsCount and TtlMinutes must be greater than zero.' AS Message;
        RETURN;
    END

    DECLARE @ExistingHash     CHAR(64);
    DECLARE @ExistingStatus   TINYINT;
    DECLARE @ExistingHttpCode INT;
    DECLARE @ExistingBody     NVARCHAR(MAX);
    DECLARE @ExistingExpires  DATETIME2(3);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Consultar y bloquear clave de idempotencia si ya existe
        SELECT
            @ExistingHash    = RequestHash,
            @ExistingStatus  = ProcessingStatus,
            @ExistingHttpCode = HttpStatusCode,
            @ExistingBody    = ResponseBody,
            @ExistingExpires = ExpiresAt
        FROM dbo.IdempotencyKeys WITH (UPDLOCK, HOLDLOCK)
        WHERE IdempotencyKey = @IdempotencyKey;

        IF @ExistingHash IS NOT NULL
        BEGIN
            -- Si expiró la retención de la clave, permitimos reutilizarla limpiamente
            IF @ExistingExpires <= @Now
            BEGIN
                DELETE FROM dbo.IdempotencyKeys WHERE IdempotencyKey = @IdempotencyKey;
                SET @ExistingHash = NULL;
            END
            ELSE
            BEGIN
                -- Misma clave pero distinto payload = petición incongruente
                IF @ExistingHash <> @RequestHash
                BEGIN
                    COMMIT TRANSACTION;
                    SELECT 422 AS ResultCode, CAST(NULL AS UNIQUEIDENTIFIER) AS ReservationId,
                           N'{"error":"Idempotency-Key was already used with a different request payload."}' AS ResponseBody,
                           N'Idempotency payload mismatch.' AS Message;
                    RETURN;
                END

                -- Ya completada anteriormente: devolver exactamente la misma respuesta sin tocar cupos
                IF @ExistingStatus = 2
                BEGIN
                    COMMIT TRANSACTION;
                    SELECT ISNULL(@ExistingHttpCode, 200) AS ResultCode,
                           CAST(NULL AS UNIQUEIDENTIFIER) AS ReservationId,
                           @ExistingBody AS ResponseBody,
                           N'Idempotent replay.' AS Message;
                    RETURN;
                END

                -- Si sigue en estado 1 (InProgress), evitar doble ejecución simultánea
                IF @ExistingStatus = 1
                BEGIN
                    COMMIT TRANSACTION;
                    SELECT 409 AS ResultCode, CAST(NULL AS UNIQUEIDENTIFIER) AS ReservationId,
                           N'{"error":"A request with this Idempotency-Key is currently being processed."}' AS ResponseBody,
                           N'Request already in progress.' AS Message;
                    RETURN;
                END
            END
        END

        -- Insertar registro de idempotencia en estado 1 (InProgress) con TTL de 24 horas
        IF @ExistingHash IS NULL
        BEGIN
            INSERT INTO dbo.IdempotencyKeys
                (IdempotencyKey, RequestHash, ProcessingStatus, CreatedAt, ExpiresAt)
            VALUES
                (@IdempotencyKey, @RequestHash, 1, @Now, DATEADD(HOUR, 24, @Now));
        END

        -- 2. Bloquear la fila del Slot (UPDLOCK + ROWLOCK) para evitar condiciones de carrera
        DECLARE @AvailableSpots INT;

        SELECT @AvailableSpots = AvailableSpots
        FROM dbo.Slots WITH (UPDLOCK, ROWLOCK)
        WHERE Id = @SlotId;

        IF @AvailableSpots IS NULL
        BEGIN
            DECLARE @NotFoundBody NVARCHAR(MAX) = N'{"error":"Slot not found."}';

            UPDATE dbo.IdempotencyKeys
            SET ProcessingStatus = 2,
                HttpStatusCode   = 404,
                ResponseBody     = @NotFoundBody
            WHERE IdempotencyKey = @IdempotencyKey;

            COMMIT TRANSACTION;
            SELECT 404 AS ResultCode, CAST(NULL AS UNIQUEIDENTIFIER) AS ReservationId,
                   @NotFoundBody AS ResponseBody, N'Slot not found.' AS Message;
            RETURN;
        END

        -- 3. Validar disponibilidad real bajo bloqueo
        IF @AvailableSpots < @SpotsCount
        BEGIN
            DECLARE @ConflictBody NVARCHAR(MAX) = N'{"error":"Insufficient available spots for this slot."}';

            UPDATE dbo.IdempotencyKeys
            SET ProcessingStatus = 2,
                HttpStatusCode   = 409,
                ResponseBody     = @ConflictBody
            WHERE IdempotencyKey = @IdempotencyKey;

            COMMIT TRANSACTION;
            SELECT 409 AS ResultCode, CAST(NULL AS UNIQUEIDENTIFIER) AS ReservationId,
                   @ConflictBody AS ResponseBody, N'Insufficient available spots.' AS Message;
            RETURN;
        END

        -- 4. Descontar cupos de forma atómica
        UPDATE dbo.Slots
        SET AvailableSpots = AvailableSpots - @SpotsCount,
            UpdatedAt      = @Now
        WHERE Id = @SlotId;

        -- 5. Insertar la reserva en estado Pending (1)
        DECLARE @NewReservationId UNIQUEIDENTIFIER = NEWID();
        DECLARE @ExpiresAt        DATETIME2(3)     = DATEADD(MINUTE, @TtlMinutes, @Now);

        INSERT INTO dbo.Reservations
            (Id, SlotId, CustomerRef, SpotsCount, Status, ExpiresAt, CreatedAt, UpdatedAt)
        VALUES
            (@NewReservationId, @SlotId, @CustomerRef, @SpotsCount, 1, @ExpiresAt, @Now, @Now);

        -- 6. Registrar transición inicial en auditoría (NULL -> 1 Pending)
        INSERT INTO dbo.ReservationAuditLogs
            (ReservationId, PreviousStatus, NewStatus, Reason, ChangedAt)
        VALUES
            (@NewReservationId, NULL, 1, N'Reservation created in Pending status', @Now);

        -- 7. Construir respuesta JSON y marcar IdempotencyKey como Completed (2)
        DECLARE @CreatedBody NVARCHAR(MAX) = (
            SELECT
                @NewReservationId AS id,
                @SlotId           AS slotId,
                @CustomerRef      AS customerRef,
                @SpotsCount       AS spotsCount,
                N'Pending'        AS status,
                @ExpiresAt        AS expiresAt,
                @Now              AS createdAt
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        UPDATE dbo.IdempotencyKeys
        SET ProcessingStatus = 2,
            HttpStatusCode   = 201,
            ResponseBody     = @CreatedBody
        WHERE IdempotencyKey = @IdempotencyKey;

        COMMIT TRANSACTION;

        SELECT 201 AS ResultCode, @NewReservationId AS ReservationId,
               @CreatedBody AS ResponseBody, N'Reservation created.' AS Message;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH
END;
GO

/* ----------------------------------------------------------------------------
   SP 2: dbo.usp_ConfirmReservation
   Confirma una reserva que esté en estado Pending (1) y aún no haya vencido.
   - No devuelve cupos (el cupo ya estaba apartado y pasa a quedar confirmado).
   - Si ya estaba Confirmed (2), responde 200 de forma segura/idempotente.
   - Si estaba Cancelled (3), Expired (4) o vencida por reloj, rechaza con 409.
   ---------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ConfirmReservation
    @ReservationId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now           DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @CurrentStatus TINYINT;
    DECLARE @ExpiresAt     DATETIME2(3);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Bloquear fila de la reserva para evitar que expira o se cancele en paralelo
        SELECT
            @CurrentStatus = Status,
            @ExpiresAt     = ExpiresAt
        FROM dbo.Reservations WITH (UPDLOCK, ROWLOCK)
        WHERE Id = @ReservationId;

        IF @CurrentStatus IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SELECT 404 AS ResultCode, N'Reservation not found.' AS Message;
            RETURN;
        END

        IF @CurrentStatus = 2
        BEGIN
            COMMIT TRANSACTION;
            SELECT 200 AS ResultCode, N'Reservation is already confirmed.' AS Message;
            RETURN;
        END

        -- Solo se puede confirmar si está en Pending (1) y no ha superado ExpiresAt
        IF @CurrentStatus <> 1 OR @ExpiresAt <= @Now
        BEGIN
            ROLLBACK TRANSACTION;
            SELECT 409 AS ResultCode,
                   N'Reservation cannot be confirmed because it is expired, cancelled, or not pending.' AS Message;
            RETURN;
        END

        UPDATE dbo.Reservations
        SET Status    = 2, -- Confirmed
            UpdatedAt = @Now
        WHERE Id = @ReservationId;

        INSERT INTO dbo.ReservationAuditLogs
            (ReservationId, PreviousStatus, NewStatus, Reason, ChangedAt)
        VALUES
            (@ReservationId, 1, 2, N'Reservation confirmed', @Now);

        COMMIT TRANSACTION;

        SELECT 200 AS ResultCode, N'Reservation confirmed successfully.' AS Message;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH
END;
GO

/* ----------------------------------------------------------------------------
   SP 3: dbo.usp_CancelReservation
   Cancela una reserva si está en Pending (1) o Confirmed (2).
   - Devuelve SpotsCount al Slot correspondiente bajo bloqueo de fila.
   - Si ya estaba Cancelled (3), responde 200 sin duplicar devolución de cupos.
   - Si ya estaba Expired (4), rechaza con 409 (el cupo ya fue liberado).
   ---------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_CancelReservation
    @ReservationId UNIQUEIDENTIFIER,
    @Reason        NVARCHAR(250) = N'Cancelled by user/system'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now           DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @CurrentStatus TINYINT;
    DECLARE @SlotId        UNIQUEIDENTIFIER;
    DECLARE @SpotsCount    INT;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT
            @CurrentStatus = Status,
            @SlotId        = SlotId,
            @SpotsCount    = SpotsCount
        FROM dbo.Reservations WITH (UPDLOCK, ROWLOCK)
        WHERE Id = @ReservationId;

        IF @CurrentStatus IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SELECT 404 AS ResultCode, N'Reservation not found.' AS Message;
            RETURN;
        END

        IF @CurrentStatus = 3
        BEGIN
            COMMIT TRANSACTION;
            SELECT 200 AS ResultCode, N'Reservation is already cancelled.' AS Message;
            RETURN;
        END

        IF @CurrentStatus = 4
        BEGIN
            ROLLBACK TRANSACTION;
            SELECT 409 AS ResultCode, N'Expired reservations cannot be cancelled.' AS Message;
            RETURN;
        END

        -- Marcar reserva como Cancelled (3)
        UPDATE dbo.Reservations
        SET Status    = 3,
            UpdatedAt = @Now
        WHERE Id = @ReservationId;

        -- Bloquear fila del Slot y devolver los cupos
        UPDATE dbo.Slots WITH (UPDLOCK, ROWLOCK)
        SET AvailableSpots = AvailableSpots + @SpotsCount,
            UpdatedAt      = @Now
        WHERE Id = @SlotId;

        INSERT INTO dbo.ReservationAuditLogs
            (ReservationId, PreviousStatus, NewStatus, Reason, ChangedAt)
        VALUES
            (@ReservationId, @CurrentStatus, 3, ISNULL(NULLIF(LTRIM(RTRIM(@Reason)), N''), N'Cancelled'), @Now);

        COMMIT TRANSACTION;

        SELECT 200 AS ResultCode, N'Reservation cancelled and spots released.' AS Message;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH
END;
GO

/* ----------------------------------------------------------------------------
   SP 4: dbo.usp_ExpireOverdueReservations
   Diseñado para ser invocado periódicamente por ExpiredReservationsWorker.
   - Toma un lote (@BatchSize) de reservas Pending (1) con ExpiresAt <= @Now.
   - READPAST salta filas ya bloqueadas por otro proceso en lugar de quedarse
     esperando, reduciendo contención.
   - Pasa las reservas a Expired (4), restaura cupos en dbo.Slots y registra
     cada transición en dbo.ReservationAuditLogs.
   ---------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ExpireOverdueReservations
    @BatchSize INT = 100
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @BatchSize IS NULL OR @BatchSize <= 0
        SET @BatchSize = 100;

    DECLARE @Now DATETIME2(3) = SYSUTCDATETIME();

    DECLARE @ExpiredBatch TABLE
    (
        ReservationId UNIQUEIDENTIFIER NOT NULL,
        SlotId        UNIQUEIDENTIFIER NOT NULL,
        SpotsCount    INT              NOT NULL
    );

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO @ExpiredBatch (ReservationId, SlotId, SpotsCount)
        SELECT TOP (@BatchSize)
            Id,
            SlotId,
            SpotsCount
        FROM dbo.Reservations WITH (UPDLOCK, ROWLOCK, READPAST)
        WHERE Status = 1
          AND ExpiresAt <= @Now
        ORDER BY ExpiresAt ASC;

        IF NOT EXISTS (SELECT 1 FROM @ExpiredBatch)
        BEGIN
            COMMIT TRANSACTION;
            SELECT 0 AS ExpiredCount;
            RETURN;
        END

        -- 1. Actualizar estado de las reservas vencidas a Expired (4)
        UPDATE r
        SET r.Status    = 4,
            r.UpdatedAt = @Now
        FROM dbo.Reservations r
        INNER JOIN @ExpiredBatch eb ON r.Id = eb.ReservationId
        WHERE r.Status = 1;

        -- 2. Agrupar cupos a devolver por Slot para hacer un solo UPDATE por Slot
        ;WITH SpotReturns AS
        (
            SELECT
                SlotId,
                SUM(SpotsCount) AS SpotsToRestore
            FROM @ExpiredBatch
            GROUP BY SlotId
        )
        UPDATE s
        SET s.AvailableSpots = s.AvailableSpots + sr.SpotsToRestore,
            s.UpdatedAt      = @Now
        FROM dbo.Slots s WITH (UPDLOCK, ROWLOCK)
        INNER JOIN SpotReturns sr ON s.Id = sr.SlotId;

        -- 3. Registrar auditoría (Pending 1 -> Expired 4)
        INSERT INTO dbo.ReservationAuditLogs
            (ReservationId, PreviousStatus, NewStatus, Reason, ChangedAt)
        SELECT
            ReservationId,
            1,
            4,
            N'Reservation TTL expired automatically',
            @Now
        FROM @ExpiredBatch;

        COMMIT TRANSACTION;

        SELECT COUNT(*) AS ExpiredCount FROM @ExpiredBatch;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH
END;
GO