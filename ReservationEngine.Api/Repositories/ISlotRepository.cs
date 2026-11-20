using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using ReservationEngine.Api.Models.Entities;

namespace ReservationEngine.Api.Repositories
{/// <summary>
 /// Abstracción de acceso a datos para los recursos/cupos (dbo.Slots) mediante Dapper y Stored Procedures.
 /// </summary>
    public interface ISlotRepository
    {
        /// <summary>
        /// Crea un nuevo Slot en base de datos mediante procedimiento almacenado.
        /// </summary>
        Task<Slot> CreateAsync(string name, int totalSpots, CancellationToken cancellationToken = default);

        /// <summary>
        /// Obtiene un Slot por su identificador único.
        /// </summary>
        Task<Slot?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default);

        /// <summary>
        /// Lista todos los Slots registrados.
        /// </summary>
        Task<IReadOnlyList<Slot>> GetAllAsync(CancellationToken cancellationToken = default);
    }
}