using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Threading.Tasks;

namespace ReservationEngine.Api.Repositories
{/// <summary>
 /// Abstraccion encargada de crear conexiones nuevas y limpios hacia la base de datos.
 /// Cada llamada debe envolverse en un bloque 'using' para liberar recursos correctamente.
 /// </summary>
    public interface IDbConnectionFactory
    {
        /// <summary>
        /// Crea una instancia de <see cref="IDbConnection"/> configurada para SQL Server.
        /// </summary>
        IDbConnection CreateConnection();
    }
}