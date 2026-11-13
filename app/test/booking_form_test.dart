import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owen_tours/core/api/api_client.dart';
import 'package:owen_tours/core/theme/app_theme.dart';
import 'package:owen_tours/features/auth/auth.dart';
import 'package:owen_tours/features/booking/booking_form.dart';
import 'package:owen_tours/features/booking/data.dart';
import 'package:owen_tours/features/booking/models.dart';
import 'package:owen_tours/features/trips/data.dart';
import 'package:owen_tours/features/trips/models.dart';

Map<String, dynamic> departureJson() => {
      'id': 'dep-1',
      'tripId': 'trip-1',
      'departureProvince': 'Mpumalanga',
      'departureArea': 'Mbombela',
      'meetingPlace': 'Riverside Mall',
      'departureAt': '2027-07-09T02:00:00Z',
      'returnDate': '2027-07-11',
      'capacity': 30,
      'seatsBooked': 2,
      'seatsLeft': 28,
      'adultPriceCents': 460000,
      'childPriceCents': 460000,
      'bookingDeadline': '2027-06-25T21:59:00Z',
      'bookingOpen': true,
      'allowInstalments': true,
      'depositCents': 100000,
      'finalPaymentDue': '2027-06-30',
      'isCancellable': true,
      'cancellationDeadline': '2027-06-25T21:59:00Z',
      'refundType': 'full',
      'refundPercent': null,
      'depositRefundable': false,
      'cancellationNotes': null,
      'policyText': 'Free cancellation until 25 Jun 2027 – 100% refund, deposit not refundable.',
      'policyBadge': 'Free cancellation',
      'isCancelledByCompany': false,
    };

TripDetail trip({required String country}) => TripDetail.fromJson({
      'id': 'trip-1',
      'title': 'Lesotho – Afriski Snow Trip',
      'destination': 'Afriski, Lesotho',
      'destinationCountry': country,
      'isCrossBorder': country != 'South Africa',
      'category': 'snow',
      'audience': 'everyone',
      'activities': <String>[],
      'description': '',
      'included': {'mealsSummary': 'Breakfast', 'breakfast': true},
      'images': <dynamic>[],
      'itinerary': <dynamic>[],
      'departures': [departureJson()],
      'specials': <dynamic>[],
      'reviewCount': 0,
      'isPublished': true,
    });

class FakeRepo extends BookingRepository {
  FakeRepo() : super(Api(Dio()));

  @override
  Future<PricePreview> preview({
    required String departureId,
    required int adults,
    required int children,
    String? promoCode,
    bool wantsStudentDiscount = false,
  }) async =>
      PricePreview.fromJson({
        'adults': adults,
        'children': children,
        'adultPriceCents': 460000,
        'childPriceCents': 460000,
        'subtotalCents': 460000 * (adults + children),
        'discountCents': 0,
        'totalCents': 460000 * (adults + children),
        'depositCents': 100000 * (adults + children),
        'balanceAfterDepositCents': 360000 * (adults + children),
        'instalmentsAvailable': true,
        'instalmentPlan': <dynamic>[],
        'policyText': 'Free cancellation until 25 Jun 2027 – 100% refund, deposit not refundable.',
        'seatsLeft': 28,
      });
}

Widget app(TripDetail t) => ProviderScope(
      overrides: [
        tripDetailProvider('trip-1').overrideWith((ref) async => t),
        bookingRepositoryProvider.overrideWithValue(FakeRepo()),
        meProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const BookingFormScreen(tripId: 'trip-1', departureId: 'dep-1')),
    );

void main() {
  testWidgets('booking button stays disabled until the cancellation policy is accepted', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(app(trip(country: 'South Africa')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // price preview debounce
    await tester.pumpAndSettle();

    CtaButton cta() => tester.widget<CtaButton>(find.byType(CtaButton));
    expect(cta().onPressed, isNull);

    await tester.tap(find.text('I have read and agree to the cancellation policy'));
    await tester.pumpAndSettle();
    expect(cta().onPressed, isNotNull);
  });

  testWidgets('cross-border trips ask for passport number and expiry', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(app(trip(country: 'Lesotho')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Passport number'), findsOneWidget);
    expect(find.text('Passport expiry date'), findsOneWidget);
    expect(find.textContaining('Every traveller needs a valid passport'), findsOneWidget);
  });
}
