using System;
using System.Data;
using Microsoft.Data.SqlClient;

namespace ReservationEngine.Api.Repositories
{/// <summary>
 /// IMPLEMENTACION de <see cref="IDbConnectionFactory"/> para SQL Server usando Microsoft.Data.SqlClient
 /// </summary>
    public sealed class SqlConnectionFactory : IDbConnectionFactory
    {
        private const string DefaultConnectionStringName = "SqlServer";
        private readonly string _connectionString;

        public SqlConnectionFactory(IConfiguration configuration)
        {
            ArgumentNullException.ThrowIfNull(configuration);

            _connectionString = configuration.GetConnectionString(DefaultConnectionStringName)
                ?? throw new InvalidOperationException(
                    $"Connection string '{DefaultConnectionStringName}' is missing in configuration.");
        }

        /// <inheritdoc />
        public IDbConnection CreateConnection()
        {
            return new SqlConnection(_connectionString);
        }
    }
}