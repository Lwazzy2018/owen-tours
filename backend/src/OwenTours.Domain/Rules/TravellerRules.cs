using OwenTours.Domain.Common;

namespace OwenTours.Domain.Rules;

public sealed record TravellerInput(
    string FullName,
    string? IdNumber,
    string? PassportNumber,
    DateOnly? PassportExpiry,
    string? Phone,
    bool IsChild,
    DateOnly? DateOfBirth,
    int? SchoolGrade,
    string? MedicalNotes,
    string? Allergies);

public sealed record GuardianInput(
    string GuardianName,
    string GuardianPhone,
    string GuardianRelationship,
    string EmergencyContactName,
    string EmergencyContactPhone,
    bool ConsentGiven);

public sealed record TripRuleInfo(string Audience, int? MinGrade, int? MaxGrade, bool IsCrossBorder);

public static class TravellerRules
{
    /// <summary>
    /// Checks every traveller against the trip's rules:
    /// cross-border trips need valid passports, adults-only trips need everyone 18+,
    /// and high school camps need guardian consent, grades and medical details.
    /// </summary>
    public static RuleResult Validate(
        TripRuleInfo trip,
        DateOnly departureDate,
        DateOnly returnDate,
        IReadOnlyList<TravellerInput> travellers,
        GuardianInput? guardian)
    {
        var r = new RuleResult();
        if (travellers.Count == 0)
        {
            r.Error("travellers", "Add at least one traveller.");
            return r;
        }

        for (var i = 0; i < travellers.Count; i++)
        {
            var t = travellers[i];
            var f = $"travellers[{i}]";
            var who = string.IsNullOrWhiteSpace(t.FullName) ? $"Traveller {i + 1}" : t.FullName.Trim();

            if (string.IsNullOrWhiteSpace(t.FullName))
                r.Error($"{f}.fullName", $"Enter the full name of traveller {i + 1}.");

            // Identity documents
            if (trip.IsCrossBorder)
            {
                if (string.IsNullOrWhiteSpace(t.PassportNumber))
                    r.Error($"{f}.passportNumber", $"{who} needs a passport number for this cross-border trip.");
                if (t.PassportExpiry is null)
                    r.Error($"{f}.passportExpiry", $"Enter the passport expiry date for {who}.");
                else if (t.PassportExpiry.Value < returnDate)
                    r.Error($"{f}.passportExpiry", $"{who}'s passport expires before the trip ends. Please renew it first.");
                else if (t.PassportExpiry.Value < returnDate.AddMonths(BookingRules.PassportWarningMonths))
                    r.Warning($"{f}.passportExpiry",
                        $"{who}'s passport expires within {BookingRules.PassportWarningMonths} months of the trip. Some borders may refuse entry – please check.");
            }
            else if (string.IsNullOrWhiteSpace(t.IdNumber) && string.IsNullOrWhiteSpace(t.PassportNumber))
            {
                r.Error($"{f}.idNumber", $"Enter an SA ID number or passport number for {who}.");
            }

            DateOnly? idBirthDate = null;
            if (!string.IsNullOrWhiteSpace(t.IdNumber))
            {
                if (!SaIdNumber.TryParse(t.IdNumber, departureDate, out var birth))
                    r.Error($"{f}.idNumber", $"{who}'s SA ID number doesn't look right. Please check it.");
                else
                    idBirthDate = birth;
            }

            var birthDate = t.DateOfBirth ?? idBirthDate;
            int? age = birthDate is null ? null : AgeOn(birthDate.Value, departureDate);

            if (age is not null && age < 0)
                r.Error($"{f}.dateOfBirth", $"{who}'s date of birth is in the future.");

            // Child pricing: someone 18 or older can't be booked as a child.
            if (t.IsChild && age is >= BookingRules.AdultAge)
                r.Error($"{f}.isChild", $"{who} is {age} on the departure date and can't be booked at the child price.");

            switch (trip.Audience)
            {
                case Audience.AdultsOnly:
                    if (t.IsChild)
                        r.Error($"{f}.isChild", "This trip is for adults only (18+).");
                    else if (age is null)
                        r.Error($"{f}.dateOfBirth", $"Enter {who}'s date of birth – this trip is for adults only (18+).");
                    else if (age < BookingRules.AdultAge)
                        r.Error($"{f}.dateOfBirth", $"{who} is under 18. This trip is for adults only.");
                    break;

                case Audience.HighSchool:
                    if (t.DateOfBirth is null)
                        r.Error($"{f}.dateOfBirth", $"Enter {who}'s date of birth.");
                    if (t.SchoolGrade is null)
                        r.Error($"{f}.schoolGrade", $"Enter {who}'s school grade.");
                    else if (t.SchoolGrade < trip.MinGrade || t.SchoolGrade > trip.MaxGrade)
                        r.Error($"{f}.schoolGrade",
                            $"This camp is for Grade {trip.MinGrade} to {trip.MaxGrade}. {who} is in Grade {t.SchoolGrade}.");
                    if (string.IsNullOrWhiteSpace(t.MedicalNotes))
                        r.Error($"{f}.medicalNotes", $"Enter {who}'s medical conditions (or \"None\").");
                    if (string.IsNullOrWhiteSpace(t.Allergies))
                        r.Error($"{f}.allergies", $"Enter {who}'s allergies (or \"None\").");
                    break;
            }
        }

        if (trip.Audience == Audience.HighSchool)
        {
            if (guardian is null)
            {
                r.Error("guardian", "A parent or guardian must complete the guardian details for this camp.");
            }
            else
            {
                if (string.IsNullOrWhiteSpace(guardian.GuardianName)) r.Error("guardian.guardianName", "Enter the guardian's name.");
                if (string.IsNullOrWhiteSpace(guardian.GuardianPhone)) r.Error("guardian.guardianPhone", "Enter the guardian's phone number.");
                if (string.IsNullOrWhiteSpace(guardian.GuardianRelationship)) r.Error("guardian.guardianRelationship", "Enter the guardian's relationship to the learner.");
                if (string.IsNullOrWhiteSpace(guardian.EmergencyContactName)) r.Error("guardian.emergencyContactName", "Enter an emergency contact name.");
                if (string.IsNullOrWhiteSpace(guardian.EmergencyContactPhone)) r.Error("guardian.emergencyContactPhone", "Enter an emergency contact phone number.");
                if (!guardian.ConsentGiven) r.Error("guardian.consentGiven", "The guardian must give permission for the learner to attend.");
            }
        }

        return r;
    }

    public static int AgeOn(DateOnly birthDate, DateOnly onDate)
    {
        var age = onDate.Year - birthDate.Year;
        if (onDate < birthDate.AddYears(age)) age--;
        return age;
    }
}

/// <summary>South African ID number: YYMMDD SSSS C A Z (13 digits, Luhn check digit).</summary>
public static class SaIdNumber
{
    public static bool TryParse(string? value, DateOnly referenceDate, out DateOnly birthDate)
    {
        birthDate = default;
        if (string.IsNullOrWhiteSpace(value)) return false;
        var id = value.Replace(" ", "").Trim();
        if (id.Length != 13 || !id.All(char.IsAsciiDigit)) return false;
        if (!PassesLuhn(id)) return false;

        var yy = int.Parse(id[..2]);
        var mm = int.Parse(id[2..4]);
        var dd = int.Parse(id[4..6]);
        // Two-digit year: anything after the reference year's yy belongs to the 1900s.
        var century = yy > referenceDate.Year % 100 ? 1900 : 2000;
        var year = century + yy;
        if (mm is < 1 or > 12 || dd < 1 || dd > DateTime.DaysInMonth(year, mm)) return false;

        birthDate = new DateOnly(year, mm, dd);
        return birthDate <= referenceDate;
    }

    public static bool PassesLuhn(string digits)
    {
        var sum = 0;
        var doubleIt = false;
        for (var i = digits.Length - 1; i >= 0; i--)
        {
            var n = digits[i] - '0';
            if (doubleIt)
            {
                n *= 2;
                if (n > 9) n -= 9;
            }
            sum += n;
            doubleIt = !doubleIt;
        }
        return sum % 10 == 0;
    }
}
