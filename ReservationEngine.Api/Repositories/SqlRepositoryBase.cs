using System.Data;
using Dapper;

namespace ReservationEngine.Api.Repositories;

/// <summary>
/// Clase base para repositorios con Dapper y stored procedures.
/// Evita repetir la creacion/cierre de conexiones y el CommandDefinition en cada metodo.
/// </summary>
public abstract class SqlRepositoryBase
{
    private readonly IDbConnectionFactory _connectionFactory;

    protected SqlRepositoryBase(IDbConnectionFactory connectionFactory)
    {
        ArgumentNullException.ThrowIfNull(connectionFactory);
        _connectionFactory = connectionFactory;
    }

    /// <summary>
    /// Ejecuta un SP que siempre devuelve una sola fila y la mapea a T.
    /// </summary>
    /// <remarks>
    /// Como funciona: abre conexion con using, arma el CommandDefinition de tipo StoredProcedure
    /// y llama QuerySingleAsync. Si el SP regresa 0 filas o mas de 1, Dapper tira excepcion.
    /// Cuando usarlo: cuando esperas un unico resultado si o si, por ejemplo al crear un slot
    /// o ejecutar SPs de comando que devuelven su ResultCode y mensaje.
    /// </remarks>
    protected async Task<T> QuerySingleStoredProcedureAsync<T>(
        string storedProcedure,
        object? parameters = null,
        CancellationToken cancellationToken = default)
    {
        using IDbConnection connection = _connectionFactory.CreateConnection();

        var command = new CommandDefinition(
            commandText: storedProcedure,
            parameters: parameters,
            commandType: CommandType.StoredProcedure,
            cancellationToken: cancellationToken);

        return await connection.QuerySingleAsync<T>(command);
    }

    /// <summary>
    /// Ejecuta un SP que puede devolver una fila o nada (null si no existe).
    /// </summary>
    /// <remarks>
    /// Como funciona: abre conexion, corre QuerySingleOrDefaultAsync y mapea a T. Si no hay nada
    /// regresa null, y si regresa mas de una fila lanza excepcion.
    /// Cuando usarlo: en busquedas por id donde el registro podria no existir, como buscar un slot
    /// o una reserva por id para luego devolver 404.
    /// </remarks>
    protected async Task<T?> QuerySingleOrDefaultStoredProcedureAsync<T>(
        string storedProcedure,
        object? parameters = null,
        CancellationToken cancellationToken = default)
    {
        using IDbConnection connection = _connectionFactory.CreateConnection();

        var command = new CommandDefinition(
            commandText: storedProcedure,
            parameters: parameters,
            commandType: CommandType.StoredProcedure,
            cancellationToken: cancellationToken);

        return await connection.QuerySingleOrDefaultAsync<T>(command);
    }

    /// <summary>
    /// Ejecuta un SP que devuelve 0, 1 o varias filas y las pasa a una lista.
    /// </summary>
    /// <remarks>
    /// Como funciona: abre conexion, ejecuta QueryAsync y hace .ToList() antes de salir del using
    /// para materializar todo mientras la conexion sigue abierta. Si no hay filas devuelve lista vacia.
    /// Cuando usarlo: para listados o historiales, como listar slots o traer logs de auditoria.
    /// </remarks>
    protected async Task<IReadOnlyList<T>> QueryListStoredProcedureAsync<T>(
        string storedProcedure,
        object? parameters = null,
        CancellationToken cancellationToken = default)
    {
        using IDbConnection connection = _connectionFactory.CreateConnection();

        var command = new CommandDefinition(
            commandText: storedProcedure,
            parameters: parameters,
            commandType: CommandType.StoredProcedure,
            cancellationToken: cancellationToken);

        IEnumerable<T> rows = await connection.QueryAsync<T>(command);
        return rows.ToList();
    }
}