namespace ReservationEngine.Api.Models.Enums
{
    public enum ReservationStatus : byte
    {
        Pending = 1,
        Confirmed = 2,
        Cancelled = 3,
        Expired = 4
    }
}