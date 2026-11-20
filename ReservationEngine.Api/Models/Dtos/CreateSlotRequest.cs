using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Threading.Tasks;

namespace ReservationEngine.Api.Models.Dtos
{
    /// <summary>
    /// Contrato de entrada para registrar un nuevo Slot con cupos limitados
    /// </summary>
    public sealed record CreateSlotRequest(
        [property: Required, StringLength(150, MinimumLength = 2)]
    string Name,

        [property: Range(1, int.MaxValue, ErrorMessage = "Total de Spots debe ser mayor que cero.")]
    int TotalSpots
    );
}