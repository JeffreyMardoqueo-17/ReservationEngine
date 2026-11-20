using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using ReservationEngine.Api.Models.Enums;

namespace ReservationEngine.Api.Models.Entities
{
    /// <summary>
    /// Representa una reserva asociada a un Slot en dbo.Reservations.
    /// </summary>
    public class Reservation
    {
        public Guid Id { get; init; }
        public Guid SlotId { get; init; }
        public string CustomerRef { get; set; } = string.Empty;
        public int SpotsCount { get; set; }
        public ReservationStatus Status { get; set; }
        public DateTime ExpiresAt { get; set; }
        public DateTime CreatedAt { get; init; }
        public DateTime UpdatedAt { get; set; }
    }
}