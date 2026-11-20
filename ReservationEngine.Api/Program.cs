using Microsoft.OpenApi;
using ReservationEngine.Api.Repositories;
using ReservationEngine.Api.Services;

var builder = WebApplication.CreateBuilder(args);

// Factory como singleton: crea conexiones nuevas por operacion sin compartir SqlConnection entre hilos
builder.Services.AddSingleton<IDbConnectionFactory, SqlConnectionFactory>();

// Repositorios y servicios con Scoped: viven lo que dura cada peticion HTTP
builder.Services.AddScoped<ISlotRepository, SlotRepository>();
builder.Services.AddScoped<ISlotService, SlotService>();

builder.Services.AddControllers();

// Swagger
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "Reservation Engine API",
        Version = "v1",
        Description = "API de control de cupos y reservas con concurrencia, idempotencia y auditoria en SQL Server."
    });
});

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI(options =>
    {
        options.SwaggerEndpoint("/swagger/v1/swagger.json", "Reservation Engine API v1");
        options.RoutePrefix = "swagger";
    });
}

app.UseHttpsRedirection();

app.UseAuthorization();

app.MapControllers();

app.Run();