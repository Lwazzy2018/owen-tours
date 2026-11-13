using OwenTours.Domain.Common;
using OwenTours.Domain.Rules;
using Xunit;
using static OwenTours.Domain.Tests.TestData;

namespace OwenTours.Domain.Tests;

public class TravellerRulesTests
{
    private static readonly DateOnly Departs = new(2027, 7, 9);
    private static readonly DateOnly Returns = new(2027, 7, 11);
    private static readonly TripRuleInfo Local = new(Audience.Everyone, null, null, false);
    private static readonly TripRuleInfo CrossBorder = new(Audience.Everyone, null, null, true);
    private static readonly TripRuleInfo AdultsOnly = new(Audience.AdultsOnly, null, null, false);
    private static readonly TripRuleInfo Camp = new(Audience.HighSchool, 8, 12, false);

    [Fact]
    public void Local_trip_with_valid_id_passes()
    {
        Assert.True(TravellerRules.Validate(Local, Departs, Returns, [Adult()], null).IsValid);
    }

    [Fact]
    public void Local_trip_needs_an_id_or_passport()
    {
        var r = TravellerRules.Validate(Local, Departs, Returns, [Adult(id: null)], null);
        Assert.Contains(r.Errors, e => e.Field == "travellers[0].idNumber");
    }

    [Fact]
    public void Invalid_sa_id_number_is_rejected()
    {
        var r = TravellerRules.Validate(Local, Departs, Returns, [Adult(id: "8001015009088")], null);
        Assert.Contains(r.Errors, e => e.Field == "travellers[0].idNumber");
    }

    [Fact]
    public void Cross_border_trip_needs_a_passport()
    {
        var r = TravellerRules.Validate(CrossBorder, Departs, Returns, [Adult()], null);
        Assert.Contains(r.Errors, e => e.Field == "travellers[0].passportNumber");
        Assert.Contains(r.Errors, e => e.Field == "travellers[0].passportExpiry");
    }

    [Fact]
    public void Passport_expiring_before_return_is_an_error()
    {
        var r = TravellerRules.Validate(CrossBorder, Departs, Returns, [Adult(passport: "A1", expiry: new DateOnly(2027, 7, 10))], null);
        Assert.Contains(r.Errors, e => e.Field == "travellers[0].passportExpiry");
    }

    [Fact]
    public void Passport_expiring_within_six_months_is_a_warning_only()
    {
        var r = TravellerRules.Validate(CrossBorder, Departs, Returns, [Adult(passport: "A1", expiry: new DateOnly(2027, 12, 1))], null);
        Assert.True(r.IsValid);
        Assert.Single(r.Warnings);
    }

    [Fact]
    public void Passport_valid_for_longer_has_no_warning()
    {
        var r = TravellerRules.Validate(CrossBorder, Departs, Returns, [Adult(passport: "A1", expiry: new DateOnly(2030, 1, 1))], null);
        Assert.True(r.IsValid);
        Assert.Empty(r.Warnings);
    }

    [Fact]
    public void Adults_only_rejects_under_18_from_the_id_number()
    {
        // 0901015009086 → born 1 Jan 2009, 18 on 1 Jan 2027 → allowed on 9 July 2027
        Assert.True(TravellerRules.Validate(AdultsOnly, Departs, Returns, [Adult(id: "0901015009086")], null).IsValid);
        // Same person on a trip in 2026 is 17
        var r = TravellerRules.Validate(AdultsOnly, new DateOnly(2026, 12, 1), new DateOnly(2026, 12, 2), [Adult(id: "0901015009086")], null);
        Assert.Contains(r.Errors, e => e.Message.Contains("under 18"));
    }

    [Fact]
    public void Adults_only_needs_a_date_of_birth_when_only_a_passport_is_given()
    {
        var r = TravellerRules.Validate(AdultsOnly, Departs, Returns, [Adult(id: null, passport: "A1")], null);
        Assert.Contains(r.Errors, e => e.Field == "travellers[0].dateOfBirth");
    }

    [Fact]
    public void An_adult_cannot_be_booked_at_the_child_price()
    {
        var adultAsChild = Adult() with { IsChild = true };
        var r = TravellerRules.Validate(Local, Departs, Returns, [adultAsChild], null);
        Assert.Contains(r.Errors, e => e.Field == "travellers[0].isChild");
    }

    [Fact]
    public void Youth_camp_with_guardian_and_learner_details_passes()
    {
        var r = TravellerRules.Validate(Camp, Departs, Returns, [Learner()], Guardian());
        Assert.True(r.IsValid);
    }

    [Fact]
    public void Youth_camp_needs_a_guardian()
    {
        var r = TravellerRules.Validate(Camp, Departs, Returns, [Learner()], null);
        Assert.Contains(r.Errors, e => e.Field == "guardian");
    }

    [Fact]
    public void Youth_camp_needs_guardian_consent()
    {
        var r = TravellerRules.Validate(Camp, Departs, Returns, [Learner()], Guardian(consent: false));
        Assert.Contains(r.Errors, e => e.Field == "guardian.consentGiven");
    }

    [Theory]
    [InlineData(7)]
    [InlineData(13)]
    public void Youth_camp_checks_the_grade_range(int grade)
    {
        var r = TravellerRules.Validate(Camp, Departs, Returns, [Learner(grade: grade)], Guardian());
        Assert.Contains(r.Errors, e => e.Field == "travellers[0].schoolGrade");
    }

    [Fact]
    public void Youth_camp_needs_medical_and_allergy_details()
    {
        var r = TravellerRules.Validate(Camp, Departs, Returns, [Learner(medical: " ", allergies: null)], Guardian());
        Assert.Contains(r.Errors, e => e.Field == "travellers[0].medicalNotes");
        Assert.Contains(r.Errors, e => e.Field == "travellers[0].allergies");
    }

    [Fact]
    public void Sa_id_parsing()
    {
        Assert.True(SaIdNumber.TryParse("8001015009087", new DateOnly(2026, 11, 10), out var birth));
        Assert.Equal(new DateOnly(1980, 1, 1), birth);
        Assert.False(SaIdNumber.TryParse("80010150090", new DateOnly(2026, 11, 10), out _));   // too short
        Assert.False(SaIdNumber.TryParse("8013015009080", new DateOnly(2026, 11, 10), out _)); // month 13
    }

    [Fact]
    public void Age_calculation()
    {
        Assert.Equal(17, TravellerRules.AgeOn(new DateOnly(2009, 7, 10), new DateOnly(2027, 7, 9)));
        Assert.Equal(18, TravellerRules.AgeOn(new DateOnly(2009, 7, 9), new DateOnly(2027, 7, 9)));
    }
}
