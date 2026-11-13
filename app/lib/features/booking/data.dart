import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import 'models.dart';

final myBookingsProvider = FutureProvider.autoDispose<List<BookingSummary>>((ref) {
  return ref.watch(apiProvider).get('/api/bookings/me', (d) => asList(d, BookingSummary.fromJson));
});

final bookingProvider = FutureProvider.autoDispose.family<Booking, String>((ref, id) {
  return ref.watch(apiProvider).get('/api/bookings/$id', (d) => Booking.fromJson(asJson(d)));
});

class BookingRepository {
  BookingRepository(this._api);
  final Api _api;

  Future<PricePreview> preview({
    required String departureId,
    required int adults,
    required int children,
    String? promoCode,
    bool wantsStudentDiscount = false,
  }) =>
      _api.post('/api/bookings/price-preview', (d) => PricePreview.fromJson(asJson(d)), body: {
        'departureId': departureId,
        'adults': adults,
        'children': children,
        'promoCode': promoCode,
        'wantsStudentDiscount': wantsStudentDiscount,
      });

  /// Returns the new booking and any warnings (e.g. passport expiring soon).
  Future<(Booking, List<String>)> create(Json body) => _api.post('/api/bookings', (d) {
        final j = asJson(d);
        return (Booking.fromJson(asJson(j['booking'])), asStrings(j['warnings']));
      }, body: body);

  Future<PaymentRedirect> pay(String bookingId, String type) =>
      _api.post('/api/bookings/$bookingId/pay', (d) => PaymentRedirect.fromJson(asJson(d)), body: {'type': type});

  Future<CancelPreview> cancelPreview(String bookingId) =>
      _api.get('/api/bookings/$bookingId/cancel-preview', (d) => CancelPreview.fromJson(asJson(d)));

  Future<Booking> cancel(String bookingId, String? reason) =>
      _api.post('/api/bookings/$bookingId/cancel', (d) => Booking.fromJson(asJson(d)), body: {'reason': reason});

  Future<void> uploadStudentId(String bookingId, List<int> bytes, String filename, String contentType) =>
      _api.upload('/api/bookings/$bookingId/student-id', (_) {}, bytes: bytes, filename: filename, contentType: contentType);

  Future<List<int>> invoice(String bookingId) => _api.download('/api/bookings/$bookingId/invoice');

  Future<void> review(String tripId, int rating, String? comment) =>
      _api.post('/api/trips/$tripId/reviews', (_) {}, body: {'rating': rating, 'comment': comment});
}

final bookingRepositoryProvider = Provider((ref) => BookingRepository(ref.watch(apiProvider)));
