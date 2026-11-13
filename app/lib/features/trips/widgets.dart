import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import 'models.dart';

class TripCard extends StatelessWidget {
  const TripCard({super.key, required this.trip, required this.onTap});
  final TripSummary trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final seats = trip.seatsLeftNext;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            AspectRatio(aspectRatio: 16 / 9, child: NetImage(trip.coverImageUrl)),
            if (trip.specialBadge != null)
              Positioned(left: 12, top: 12, child: Pill(trip.specialBadge!, icon: Icons.local_offer, tone: PillTone.accent)),
            if (seats != null && seats > 0 && seats <= 5)
              Positioned(right: 12, top: 12, child: Pill('Only $seats seats left', tone: PillTone.accent)),
            if (seats == 0) const Positioned(right: 12, top: 12, child: Pill('Fully booked', tone: PillTone.danger)),
          ]),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(trip.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(trip.destination, style: const TextStyle(color: AppColors.secondaryText)),
              if (trip.departsFrom.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.directions_bus_outlined, size: 16, color: AppColors.teal),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('Departs from ${trip.departsFrom.join(' · ')}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  ),
                ]),
              ],
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (trip.transportIncluded) const Pill('Transport', icon: Icons.directions_bus, tone: PillTone.success),
                if (trip.mealsSummary != 'No meals included') Pill(trip.mealsSummary, icon: Icons.restaurant, tone: PillTone.success),
                if (trip.accommodationIncluded) const Pill('Accommodation', icon: Icons.hotel, tone: PillTone.success),
                if (trip.cancellationBadge != null)
                  Pill(trip.cancellationBadge!, tone: trip.cancellationBadge == 'Free cancellation' ? PillTone.info : PillTone.neutral),
                if (trip.isCrossBorder) Pill('Passport needed · ${trip.destinationCountry}', icon: Icons.badge_outlined, tone: PillTone.sand),
                if (trip.audience == 'high_school') const Pill('High school learners', tone: PillTone.sand),
                if (trip.audience == 'adults_only') const Pill('18+', tone: PillTone.sand),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                if (trip.nextDepartureAt != null)
                  Expanded(
                    child: Text('Next: ${formatDay(trip.nextDepartureAt!)}', style: const TextStyle(color: AppColors.secondaryText)),
                  )
                else
                  const Expanded(child: Text('New dates coming soon', style: TextStyle(color: AppColors.secondaryText))),
                if (trip.fromPriceCents != null)
                  Text.rich(TextSpan(children: [
                    const TextSpan(text: 'from ', style: TextStyle(color: AppColors.secondaryText)),
                    TextSpan(
                      text: randShort(trip.fromPriceCents!),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.deepBlue),
                    ),
                  ])),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The "What's included" section with clear icons; things not included are shown clearly too.
class WhatsIncludedSection extends StatelessWidget {
  const WhatsIncludedSection({super.key, required this.included});
  final WhatsIncluded included;

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, bool yes, String title, String? detail) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: yes ? AppColors.teal : AppColors.secondaryText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: yes ? AppColors.deepBlue : AppColors.secondaryText)),
                if (detail != null && detail.isNotEmpty) Text(detail, style: const TextStyle(color: AppColors.secondaryText)),
              ]),
            ),
            Icon(yes ? Icons.check_circle : Icons.remove_circle_outline, color: yes ? AppColors.green : AppColors.secondaryText, size: 20),
          ]),
        );

    return SandBox(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        row(Icons.directions_bus, included.transportIncluded,
            included.transportIncluded ? 'Transport included – ${titleCase(included.transportType ?? 'bus')}' : 'Transport not included',
            included.transportNotes),
        row(Icons.restaurant, included.anyMeals, 'Meals: ${included.mealsSummary}', included.mealsNotes),
        row(Icons.hotel, included.accommodationIncluded,
            included.accommodationIncluded
                ? 'Accommodation – ${titleCase(included.accommodationType ?? 'included')}'
                : 'Accommodation not included',
            included.accommodationNotes),
        for (final extra in included.otherIncludes) row(Icons.check, true, extra, null),
        if (included.excludes.isNotEmpty) ...[
          const Divider(height: 24),
          const Text('Not included', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          for (final x in included.excludes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                const Icon(Icons.close, size: 16, color: AppColors.secondaryText),
                const SizedBox(width: 8),
                Expanded(child: Text(x)),
              ]),
            ),
        ],
      ]),
    );
  }
}

class DepartureCard extends StatelessWidget {
  const DepartureCard({super.key, required this.departure, required this.onBook});
  final Departure departure;
  final VoidCallback? onBook;

  @override
  Widget build(BuildContext context) {
    final d = departure;
    final lowSeats = d.seatsLeft > 0 && d.seatsLeft <= 5;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(formatDay(d.departureAt), style: Theme.of(context).textTheme.titleMedium)),
            if (d.isCancelledByCompany)
              const Pill('Cancelled', tone: PillTone.danger)
            else if (d.seatsLeft == 0)
              const Pill('Fully booked', tone: PillTone.danger)
            else
              Pill('${d.seatsLeft} seats left', tone: lowSeats ? PillTone.accent : PillTone.info),
          ]),
          const SizedBox(height: 8),
          _iconLine(Icons.place_outlined, 'Departs from ${d.departsFrom}'),
          _iconLine(Icons.meeting_room_outlined, '${d.meetingPlace} · ${formatTime(d.departureAt)}'),
          _iconLine(Icons.event_available_outlined, 'Returns ${formatDateOnly(d.returnDate)}'),
          const SizedBox(height: 8),
          Row(children: [
            Text(rand(d.adultPriceCents), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
            const Text(' per adult', style: TextStyle(color: AppColors.secondaryText)),
            if (d.childPriceCents != d.adultPriceCents)
              Text(' · ${rand(d.childPriceCents)} per child', style: const TextStyle(color: AppColors.secondaryText)),
          ]),
          if (d.allowInstalments && d.depositCents > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Pay in instalments: ${rand(d.depositCents)} deposit per person, the rest monthly',
                  style: const TextStyle(color: AppColors.teal, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(d.isCancellable ? Icons.event_busy_outlined : Icons.block, size: 18, color: AppColors.secondaryText),
            const SizedBox(width: 6),
            Expanded(child: Text(d.policyText, style: const TextStyle(fontSize: 13))),
          ]),
          const SizedBox(height: 4),
          Text('Book by ${formatDateTime(d.bookingDeadline)}', style: const TextStyle(fontSize: 12, color: AppColors.secondaryText)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: CtaButton(label: d.bookingOpen ? 'Book now' : 'Bookings closed', onPressed: d.bookingOpen ? onBook : null),
          ),
        ]),
      ),
    );
  }

  Widget _iconLine(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(icon, size: 16, color: AppColors.teal),
          const SizedBox(width: 6),
          Expanded(child: Text(text)),
        ]),
      );
}
