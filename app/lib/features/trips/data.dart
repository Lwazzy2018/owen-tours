import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/api_client.dart';
import '../company/data.dart';
import '../past_trips/models.dart';
import 'models.dart';

final tripFiltersProvider = StateProvider<TripFilters>((ref) => const TripFilters());

final tripsProvider = FutureProvider.autoDispose.family<Paged<TripSummary>, TripFilters>((ref, filters) {
  return ref.watch(apiProvider).get('/api/trips', (d) => Paged.fromJson(d, TripSummary.fromJson), query: filters.toQuery());
});

final tripDetailProvider = FutureProvider.autoDispose.family<TripDetail, String>((ref, id) {
  return ref.watch(apiProvider).get('/api/trips/$id', (d) => TripDetail.fromJson(asJson(d)));
});

final tripReviewsProvider = FutureProvider.autoDispose.family<List<Review>, String>((ref, id) {
  return ref.watch(apiProvider).get('/api/trips/$id/reviews', (d) => asList(d, Review.fromJson));
});

final tripPastTripsProvider = FutureProvider.autoDispose.family<List<PastTripSummary>, String>((ref, id) {
  return ref.watch(apiProvider).get('/api/trips/$id/past-trips', (d) => asList(d, PastTripSummary.fromJson));
});

final specialsProvider = FutureProvider.autoDispose<List<Special>>((ref) {
  return ref.watch(apiProvider).get('/api/specials', (d) => asList(d, Special.fromJson));
});

final departureLocationsProvider = FutureProvider<List<DepartureLocation>>((ref) {
  return ref.watch(apiProvider).get('/api/departure-locations', (d) => asList(d, DepartureLocation.fromJson));
});

/// Live "seats booked" for every departure of a trip, straight from Supabase Realtime.
/// Map of departure id → seats_booked. Falls back silently if Realtime is unavailable.
final liveSeatsProvider = StreamProvider.autoDispose.family<Map<String, int>, String>((ref, tripId) {
  return Supabase.instance.client
      .from('departures')
      .stream(primaryKey: ['id'])
      .eq('trip_id', tripId)
      .map((rows) => {for (final r in rows) r['id'] as String: (r['seats_booked'] as num).toInt()});
});

/// Re-export so screens can import one file.
final companyInfoProvider = companyProvider;
