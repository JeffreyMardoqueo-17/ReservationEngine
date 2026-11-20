using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using ReservationEngine.Api.Models.Enums;

namespace ReservationEngine.Api.Models.Dtos
{
    /// <summary>
    /// Contrato de salida para consultar o devolver el estado de una reserva.
    /// </summary>
    public sealed record ReservationResponse(
        Guid Id,
        Guid SlotId,
        string CustomerRef,
        int SpotsCount,
        ReservationStatus Status,
        DateTime ExpiresAt,
        DateTime CreatedAt,
        DateTime UpdatedAt
    );
}