using System.Text.RegularExpressions;
using ReservationEngine.Api.Models.Dtos;
using ReservationEngine.Api.Models.Entities;
using ReservationEngine.Api.Repositories;

namespace ReservationEngine.Api.Services;

/// <summary>
/// Servicio de aplicacion para reglas de negocio y validaciones de slots.
/// </summary>
public partial class SlotService : ISlotService
{
    private const int MinSlotNameLength = 3;
    private const int MaxSlotNameLength = 150;
    private const int MaxTotalSpots = 100_000;

    private readonly ISlotRepository _slotRepository;
    private readonly ILogger<SlotService> _logger;

    public SlotService(ISlotRepository slotRepository, ILogger<SlotService> logger)
    {
        ArgumentNullException.ThrowIfNull(slotRepository);
        ArgumentNullException.ThrowIfNull(logger);

        _slotRepository = slotRepository;
        _logger = logger;
    }

    /// <summary>
    /// Valida, normaliza a minusculas y crea un slot usando el repositorio.
    /// </summary>
    /// <remarks>
    /// Como funciona: revisa el request, limpia y normaliza el nombre a minusculas, valida los cupos
    /// y llama al repositorio sin meterse en detalles de base de datos.
    /// Cuando usarlo: al crear un nuevo slot desde el controlador o capa superior.
    /// </remarks>
    public async Task<SlotResponse> CreateAsync(CreateSlotRequest request, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);

        string normalizedName = ValidateAndNormalizeName(request.Name);
        ValidateTotalSpots(request.TotalSpots);

        try
        {
            Slot createdSlot = await _slotRepository.CreateAsync(
                normalizedName,
                request.TotalSpots,
                cancellationToken);

            _logger.LogInformation(
                "Slot creado. SlotId: {SlotId}, TotalSpots: {TotalSpots}",
                createdSlot.Id,
                createdSlot.TotalSpots);

            return MapToResponse(createdSlot);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error al crear slot con nombre normalizado '{SlotName}'", normalizedName);
            throw;
        }
    }

    /// <summary>
    /// Consulta un slot por su id validando que no venga vacio.
    /// </summary>
    /// <remarks>
    /// Como funciona: comprueba que el id no sea Guid.Empty, pide el registro al repositorio
    /// y devuelve null si no existe o el SlotResponse si lo encuentra.
    /// Cuando usarlo: cuando se solicita consultar un slot especifico por su identificador.
    /// </remarks>
    public async Task<SlotResponse?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default)
    {
        if (id == Guid.Empty)
            throw new ArgumentException("El id del slot no puede estar vacio.", nameof(id));
        

        try
        {
            Slot? slot = await _slotRepository.GetByIdAsync(id, cancellationToken);
            return slot is null ? null : MapToResponse(slot);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error al consultar slot con id {SlotId}", id);
            throw;
        }
    }

    /// <summary>
    /// Lista todos los slots registrados
    /// </summary>
    /// <remarks>
    /// Como funciona: llama al repositorio para obtener los slots y los convierte a SlotResponse.
    /// Cuando usarlo: cuando se necesita listar los slots disponibles
    /// </remarks>
    public async Task<IReadOnlyList<SlotResponse>> GetAllAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            IReadOnlyList<Slot> slots = await _slotRepository.GetAllAsync(cancellationToken);

            return slots
                .Select(MapToResponse)
                .ToList();
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error al listar los slots");
            throw;
        }
    }

    private static string ValidateAndNormalizeName(string? rawName)
    {
        if (string.IsNullOrWhiteSpace(rawName))
            throw new ArgumentException("El nombre del slot es obligatorio.", nameof(rawName));

        if (rawName.Any(char.IsControl))
            throw new ArgumentException("El nombre del slot no puede tener caracteres de control.", nameof(rawName));
        
        string cleaned = MultipleSpacesRegex()
            .Replace(rawName.Trim(), " ")
            .ToLowerInvariant();

        if (cleaned.Length < MinSlotNameLength || cleaned.Length > MaxSlotNameLength)
        {
            throw new ArgumentException(
                $"El nombre del slot debe tener entre {MinSlotNameLength} y {MaxSlotNameLength} caracteres.",
                nameof(rawName));
        }

        if (!AllowedSlotNameRegex().IsMatch(cleaned))
        {
            throw new ArgumentException(
                "El nombre del slot solo puede tener letras (a-z), numeros, espacios, guion y guion bajo, sin simbolos.",
                nameof(rawName));
        }

        return cleaned;
    }

    private static void ValidateTotalSpots(int totalSpots)
    {
        if (totalSpots <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(totalSpots),
                "La cantidad total de cupos debe ser mayor a cero.");
        }

        if (totalSpots > MaxTotalSpots)
        {
            throw new ArgumentOutOfRangeException(
                nameof(totalSpots),
                $"La cantidad total de cupos no puede superar {MaxTotalSpots}.");
        }
    }

    private static SlotResponse MapToResponse(Slot slot)
    {
        return new SlotResponse(
            Id: slot.Id,
            Name: slot.Name,
            TotalSpots: slot.TotalSpots,
            AvailableSpots: slot.AvailableSpots,
            CreatedAt: slot.CreatedAt,
            UpdatedAt: slot.UpdatedAt);
    }

    [GeneratedRegex(@"^[a-z0-9 _-]+$")]
    private static partial Regex AllowedSlotNameRegex();

    [GeneratedRegex(@"\s+")]
    private static partial Regex MultipleSpacesRegex();
}