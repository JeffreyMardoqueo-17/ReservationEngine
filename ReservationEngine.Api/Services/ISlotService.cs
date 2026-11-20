using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using ReservationEngine.Api.Models.Dtos;

namespace ReservationEngine.Api.Services
{/// <summary>
 /// Contrato de negocio para gestionar los slots de cupos.
 /// </summary>
    public interface ISlotService
    {
        /// <summary>
        /// Crea un nuevo slot validando las reglas de negocio iniciales.
        /// </summary>
        /// <remarks>
        /// Como funciona: revisa los datos de entrada, llama al repositorio para guardar el slot y lo mapea a SlotResponse.
        /// Cuando usarlo: cuando llega una peticion para dar de alta un recurso o bloque con cupos limitados.
        /// </remarks>
        Task<SlotResponse> CreateAsync(CreateSlotRequest request, CancellationToken cancellationToken = default);

        /// <summary>
        /// Busca un slot por su id.
        /// </summary>
        /// <remarks>
        /// Como funciona: valida que el id sea valido y consulta el repositorio; si no existe regresa null.
        /// Cuando usarlo: al consultar el detalle o disponibilidad actual de un slot puntual.
        /// </remarks>
        Task<SlotResponse?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default);

        /// <summary>
        /// Obtiene todos los slots registrados.
        /// </summary>
        /// <remarks>
        /// Como funciona: pide la lista al repositorio y convierte cada entidad en su DTO de respuesta.
        /// Cuando usarlo: cuando se necesita listar todos los slots disponibles o administrados.
        /// </remarks>
        Task<IReadOnlyList<SlotResponse>> GetAllAsync(CancellationToken cancellationToken = default);
    }
}