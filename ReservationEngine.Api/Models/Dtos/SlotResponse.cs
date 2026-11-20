using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace ReservationEngine.Api.Models.Dtos
{
    /// <summary>
    /// Contrato de salida para consultar o devolver un Slot.
    /// </summary>
    public sealed record SlotResponse(
        Guid Id,
        string Name,
        int TotalSpots,
        int AvailableSpots,
        DateTime CreatedAt,
        DateTime UpdatedAt
    );
}