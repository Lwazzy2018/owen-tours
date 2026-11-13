import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../auth/auth.dart';

class _NavItem {
  const _NavItem(this.path, this.label, this.icon);
  final String path, label;
  final IconData icon;
}

const _items = [
  _NavItem('/admin', 'Dashboard', Icons.dashboard_outlined),
  _NavItem('/admin/trips', 'Trips', Icons.travel_explore),
  _NavItem('/admin/bookings', 'Bookings', Icons.confirmation_number_outlined),
  _NavItem('/admin/past-trips', 'Previous trips', Icons.photo_library_outlined),
  _NavItem('/admin/specials', 'Specials', Icons.local_offer_outlined),
  _NavItem('/admin/student-ids', 'Student IDs', Icons.badge_outlined),
  _NavItem('/admin/enquiries', 'Enquiries', Icons.inbox_outlined),
  _NavItem('/admin/settings', 'Company & staff', Icons.settings_outlined),
];

/// Only admins get in. The API enforces this too; this just shows a friendly screen.
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.child, required this.location});
  final Widget child;
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    return me.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (e, _) => Scaffold(body: ErrorView(message: ApiException.from(e).message, onRetry: () => ref.invalidate(meProvider))),
      data: (user) {
        if (user == null || !user.isAdmin) {
          return Scaffold(
            appBar: AppBar(title: const Text('Admin')),
            body: EmptyView(
              icon: Icons.lock_outline,
              title: 'Staff only',
              message: 'This area is for Owen Tours and Travel staff. Ask an admin to invite you.',
              action: FilledButton(onPressed: () => context.go(user == null ? '/login?from=/admin' : '/'), child: Text(user == null ? 'Sign in' : 'Back to the app')),
            ),
          );
        }
        final selected = _items.lastIndexWhere((i) => i.path == '/admin' ? location == '/admin' : location.startsWith(i.path));
        final wide = MediaQuery.of(context).size.width >= 900;
        final nav = [for (final i in _items) NavigationRailDestination(icon: Icon(i.icon), label: Text(i.label))];

        return Scaffold(
          appBar: AppBar(
            title: const Text('Owen Tours – Admin'),
            actions: [
              TextButton.icon(
                onPressed: () => context.go('/'),
                icon: const Icon(Icons.open_in_new, color: AppColors.white),
                label: const Text('View app', style: TextStyle(color: AppColors.white)),
              ),
            ],
          ),
          drawer: wide
              ? null
              : Drawer(
                  child: ListView(children: [
                    for (var i = 0; i < _items.length; i++)
                      ListTile(
                        selected: i == selected,
                        leading: Icon(_items[i].icon),
                        title: Text(_items[i].label),
                        onTap: () {
                          Navigator.pop(context);
                          context.go(_items[i].path);
                        },
                      ),
                  ]),
                ),
          body: Row(children: [
            if (wide)
              NavigationRail(
                extended: MediaQuery.of(context).size.width >= 1200,
                selectedIndex: selected < 0 ? 0 : selected,
                destinations: nav,
                onDestinationSelected: (i) => context.go(_items[i].path),
                backgroundColor: AppColors.white,
                indicatorColor: AppColors.tealTint,
              ),
            if (wide) const VerticalDivider(width: 1),
            Expanded(child: child),
          ]),
        );
      },
    );
  }
}

// ============================ Dashboard ============================

class DashboardData {
  DashboardData.fromJson(Json j)
      : revenueThisMonthCents = asInt(j['revenueThisMonthCents']),
        bookingsThisMonth = asInt(j['bookingsThisMonth']),
        activeBookings = asInt(j['activeBookings']),
        overdueInstalments = asInt(j['overdueInstalments']),
        overdueAmountCents = asInt(j['overdueAmountCents']),
        newEnquiries = asInt(j['newEnquiries']),
        pendingStudentIds = asInt(j['pendingStudentIds']),
        pendingRefunds = asInt(j['pendingRefunds']),
        upcoming = asList(j['upcomingDepartures'], (d) => d);
  final int revenueThisMonthCents, bookingsThisMonth, activeBookings, overdueInstalments, overdueAmountCents;
  final int newEnquiries, pendingStudentIds, pendingRefunds;
  final List<Json> upcoming;
}

final dashboardProvider = FutureProvider.autoDispose<DashboardData>((ref) {
  return ref.watch(apiProvider).get('/api/admin/dashboard', (d) => DashboardData.fromJson(asJson(d)));
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dashboardProvider);
    return AsyncView(
      value: data,
      onRetry: () => ref.invalidate(dashboardProvider),
      data: (d) => RefreshIndicator(
        onRefresh: () => ref.refresh(dashboardProvider.future).then((_) {}),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text('Dashboard', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Wrap(spacing: 16, runSpacing: 16, children: [
            _Stat('Revenue this month', rand(d.revenueThisMonthCents), Icons.payments_outlined),
            _Stat('Bookings this month', '${d.bookingsThisMonth}', Icons.confirmation_number_outlined),
            _Stat('Active bookings', '${d.activeBookings}', Icons.groups_outlined),
            _Stat('Overdue instalments', '${d.overdueInstalments} · ${rand(d.overdueAmountCents)}', Icons.warning_amber,
                alert: d.overdueInstalments > 0, onTap: () => context.go('/admin/bookings?status=confirmed')),
            _Stat('New enquiries', '${d.newEnquiries}', Icons.inbox_outlined, alert: d.newEnquiries > 0, onTap: () => context.go('/admin/enquiries')),
            _Stat('Student IDs to check', '${d.pendingStudentIds}', Icons.badge_outlined,
                alert: d.pendingStudentIds > 0, onTap: () => context.go('/admin/student-ids')),
            _Stat('Refunds to pay', '${d.pendingRefunds}', Icons.undo, alert: d.pendingRefunds > 0, onTap: () => context.go('/admin/bookings')),
          ]),
          const SectionTitle('Upcoming departures'),
          Card(
            child: Column(children: [
              for (final u in d.upcoming)
                ListTile(
                  title: Text(u['tripTitle'] as String),
                  subtitle: Text('${formatDateTime(DateTime.parse(u['departureAt'] as String))} · ${u['departsFrom']}'),
                  trailing: SizedBox(
                    width: 180,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('${u['seatsBooked']} / ${u['capacity']} seats · ${u['bookings']} bookings'),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: asInt(u['capacity']) == 0 ? 0 : asInt(u['seatsBooked']) / asInt(u['capacity'])),
                    ]),
                  ),
                  onTap: () => context.go('/admin/bookings?departureId=${u['departureId']}'),
                ),
              if (d.upcoming.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No upcoming departures.')),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.icon, {this.alert = false, this.onTap});
  final String label, value;
  final IconData icon;
  final bool alert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 250,
        child: Card(
          color: alert ? AppColors.coralTint : AppColors.white,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(icon, color: alert ? AppColors.coral : AppColors.teal, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: const TextStyle(color: AppColors.secondaryText, fontSize: 13)),
                    Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
}
