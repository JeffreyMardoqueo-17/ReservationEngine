using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using ReservationEngine.Api.Models.Enums;

namespace ReservationEngine.Api.Models.Entities
{
    /// <summary>
    /// Registro inmutable de cada transición de estado en dbo.ReservationAuditLogs.
    /// </summary>
    public sealed class ReservationAuditLog
    {
        public long Id { get; init; }
        public Guid ReservationId { get; init; }
        public ReservationStatus? PreviousStatus { get; init; }
        public ReservationStatus NewStatus { get; init; }
        public string Reason { get; set; } = string.Empty;
        public DateTime ChangedAt { get; init; }
    }
}