using System.Data;
using Dapper;
using ReservationEngine.Api.Models.Entities;

namespace ReservationEngine.Api.Repositories;

/// <summary>
/// Implementación de <see cref="ISlotRepository"/> basada en Dapper y Stored Procedures en SQL Server
/// </summary>
public sealed class SlotRepository : SqlRepositoryBase, ISlotRepository
{
    public SlotRepository(IDbConnectionFactory connectionFactory) : base(connectionFactory)
    {
    }

    /// <inheritdoc />
    public Task<Slot> CreateAsync(string name, int totalSpots, CancellationToken cancellationToken = default)
    {
        var parameters = new DynamicParameters();
        parameters.Add("@Name", name, DbType.String, size: 150);
        parameters.Add("@TotalSpots", totalSpots, DbType.Int32);

        return QuerySingleStoredProcedureAsync<Slot>(
            "dbo.usp_CreateSlot",
            parameters,
            cancellationToken);
    }

    /// <inheritdoc />
    public Task<Slot?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default)
    {
        var parameters = new DynamicParameters();
        parameters.Add("@Id", id, DbType.Guid);

        return QuerySingleOrDefaultStoredProcedureAsync<Slot>(
            "dbo.usp_GetSlotById",
            parameters,
            cancellationToken);
    }

    /// <inheritdoc />
    public Task<IReadOnlyList<Slot>> GetAllAsync(CancellationToken cancellationToken = default)
    {
        return QueryListStoredProcedureAsync<Slot>(
            "dbo.usp_GetAllSlots",
            cancellationToken: cancellationToken);
    }
}