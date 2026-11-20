using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Threading.Tasks;

namespace ReservationEngine.Api.Models.Dtos
{
    /// <summary>
    /// Contrato de entrada para crear una reserva de cupos en un Slot.
    /// La clave de idempotencia se envía en el header Idempotency-Key.
    /// </summary>
    public sealed record CreateReservationRequest(
        [property: Required]
    Guid SlotId,

        [property: Required, StringLength(100, MinimumLength = 1)]
    string CustomerRef,

        [property: Range(1, int.MaxValue, ErrorMessage = "SpotsCount must be greater than zero.")]
    int SpotsCount,

        [property: Range(1, 1440, ErrorMessage = "TtlMinutes must be between 1 and 1440.")]
    int TtlMinutes = 5
    );
}