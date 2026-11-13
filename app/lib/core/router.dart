import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/admin/admin_shell.dart';
import '../features/admin/bookings_admin.dart';
import '../features/admin/past_trips_admin.dart';
import '../features/admin/settings_admin.dart';
import '../features/admin/trips_admin.dart';
import '../features/auth/auth.dart';
import '../features/booking/booking_form.dart';
import '../features/booking/booking_screens.dart';
import '../features/company/screens.dart';
import '../features/past_trips/screens.dart';
import '../features/trips/screens.dart';

final _authRefresh = AuthRefresh();

/// Paths that need a signed-in user.
bool _needsSignIn(String path) =>
    path.startsWith('/my-trips') || path.startsWith('/bookings') || RegExp(r'^/trips/[^/]+/book').hasMatch(path);

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: _authRefresh,
    redirect: (context, state) {
      final signedIn = Supabase.instance.client.auth.currentSession != null;
      final path = state.uri.path;
      if (!signedIn && _needsSignIn(path)) {
        return '/login?from=${Uri.encodeComponent(state.uri.toString())}';
      }
      if (signedIn && (path == '/login' || path == '/register')) {
        return state.uri.queryParameters['from'] ?? '/';
      }
      return null;
    },
    routes: [
      // ---------------- Customer app with bottom navigation ----------------
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _CustomerShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, __) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/past-trips', builder: (_, __) => const PastTripsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/my-trips', builder: (_, __) => const MyTripsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/more', builder: (_, __) => const MoreScreen())]),
        ],
      ),
      GoRoute(path: '/trips/:id', builder: (_, s) => TripDetailScreen(tripId: s.pathParameters['id']!)),
      GoRoute(
        path: '/trips/:id/book',
        builder: (_, s) => BookingFormScreen(tripId: s.pathParameters['id']!, departureId: s.uri.queryParameters['departure']),
      ),
      GoRoute(
        path: '/bookings/:id',
        builder: (_, s) => BookingDetailScreen(bookingId: s.pathParameters['id']!, autoPay: s.uri.queryParameters['pay']),
      ),
      GoRoute(path: '/past-trips/:id', builder: (_, s) => PastTripDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(path: '/about', builder: (_, __) => const AboutScreen()),
      GoRoute(path: '/plan-trip', builder: (_, __) => const EnquiryScreen()),
      GoRoute(path: '/login', builder: (_, s) => LoginScreen(from: s.uri.queryParameters['from'])),
      GoRoute(path: '/register', builder: (_, s) => RegisterScreen(from: s.uri.queryParameters['from'])),

      // ---------------- Admin panel (Flutter Web) ----------------
      ShellRoute(
        builder: (context, state, child) => AdminShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/admin', builder: (_, __) => const DashboardScreen()),
          GoRoute(path: '/admin/trips', builder: (_, __) => const AdminTripsScreen()),
          GoRoute(path: '/admin/trips/new', builder: (_, __) => const AdminTripEditorScreen()),
          GoRoute(path: '/admin/trips/:id', builder: (_, s) => AdminTripEditorScreen(tripId: s.pathParameters['id'])),
          GoRoute(
            path: '/admin/trips/:id/departures/new',
            builder: (_, s) => AdminDepartureEditorScreen(tripId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/admin/trips/:id/departures/:depId',
            builder: (_, s) => AdminDepartureEditorScreen(tripId: s.pathParameters['id']!, departureId: s.pathParameters['depId']),
          ),
          GoRoute(
            path: '/admin/bookings',
            builder: (_, s) => AdminBookingsScreen(
              key: ValueKey(s.uri.toString()),
              initialStatus: s.uri.queryParameters['status'],
              departureId: s.uri.queryParameters['departureId'],
            ),
          ),
          GoRoute(path: '/admin/bookings/:id', builder: (_, s) => AdminBookingDetailScreen(id: s.pathParameters['id']!)),
          GoRoute(path: '/admin/past-trips', builder: (_, __) => const AdminPastTripsScreen()),
          GoRoute(path: '/admin/past-trips/new', builder: (_, __) => const AdminPastTripEditorScreen()),
          GoRoute(path: '/admin/past-trips/:id', builder: (_, s) => AdminPastTripEditorScreen(id: s.pathParameters['id'])),
          GoRoute(path: '/admin/specials', builder: (_, __) => const AdminSpecialsScreen()),
          GoRoute(path: '/admin/student-ids', builder: (_, __) => const AdminStudentIdsScreen()),
          GoRoute(path: '/admin/enquiries', builder: (_, __) => const AdminEnquiriesScreen()),
          GoRoute(path: '/admin/settings', builder: (_, __) => const AdminSettingsScreen()),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Center(child: FilledButton(onPressed: () => context.go('/'), child: const Text('Go home'))),
    ),
  );
});

class _CustomerShell extends StatelessWidget {
  const _CustomerShell({required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Explore'),
            NavigationDestination(icon: Icon(Icons.photo_library_outlined), selectedIcon: Icon(Icons.photo_library), label: 'Previous trips'),
            NavigationDestination(icon: Icon(Icons.luggage_outlined), selectedIcon: Icon(Icons.luggage), label: 'My trips'),
            NavigationDestination(icon: Icon(Icons.menu), label: 'More'),
          ],
        ),
      );
}
