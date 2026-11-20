using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace ReservationEngine.Api.Models.Entities
{/// <summary>
 /// Representa un recurso, evento o bloque con cupos limitados en dbo.Slots 
 /// </summary>
    public class Slot
    {
        public Guid Id { get; init; }
        public string Name { get; set; } = string.Empty;
        public int TotalSpots { get; set; }
        public int AvailableSpots { get; set; }
        public DateTime CreatedAt { get; init; }
        public DateTime UpdatedAt { get; set; }
    }
}