import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../company/data.dart';
import 'data.dart';
import 'models.dart';
import 'widgets.dart';

// ============================ Home / Explore ============================

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(tripFiltersProvider);
    final trips = ref.watch(tripsProvider(filters));
    final specials = ref.watch(specialsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Owen Tours and Travel', style: TextStyle(fontWeight: FontWeight.w700)),
          Text('Explore the World', style: TextStyle(fontSize: 12, color: AppColors.warmSand)),
        ]),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(specialsProvider);
          return ref.refresh(tripsProvider(filters).future).then((_) {});
        },
        child: Constrained(
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Container(
                color: AppColors.warmSand,
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Where to next?', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  const Text("Want to go on a tour but don't know where to begin? We've got you."),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search trips or destinations',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _search.clear();
                                    _apply(_copy(filters, search: ''));
                                  },
                                ),
                        ),
                        onSubmitted: (v) => _apply(_copy(filters, search: v.trim())),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Filters',
                      style: IconButton.styleFrom(backgroundColor: filters.isEmpty ? AppColors.teal : AppColors.coral),
                      onPressed: () => _openFilters(filters),
                      icon: Icon(Icons.tune, color: filters.isEmpty ? AppColors.white : AppColors.deepBlue),
                    ),
                  ]),
                ]),
              ),
            ),
            SliverToBoxAdapter(
              child: specials.maybeWhen(
                data: (list) => list.isEmpty ? const SizedBox.shrink() : _SpecialsBanner(specials: list),
                orElse: () => const SizedBox.shrink(),
              ),
            ),
            if (!filters.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Wrap(spacing: 8, children: [
                    if (filters.category != null) Pill(titleCase(filters.category!), tone: PillTone.info),
                    if (filters.province != null) Pill('From ${filters.area ?? filters.province!}', tone: PillTone.info),
                    if (filters.maxPriceCents != null) Pill('Up to ${randShort(filters.maxPriceCents!)}', tone: PillTone.info),
                    if (filters.from != null) Pill('From ${formatDay(filters.from!)}', tone: PillTone.info),
                    ActionChip(
                      label: const Text('Clear filters'),
                      onPressed: () {
                        _search.clear();
                        _apply(const TripFilters());
                      },
                    ),
                  ]),
                ),
              ),
            trips.when(
              loading: () => const SliverFillRemaining(child: LoadingView(message: 'Finding trips…')),
              error: (e, _) => SliverFillRemaining(
                child: ErrorView(message: e.toString(), onRetry: () => ref.invalidate(tripsProvider(filters))),
              ),
              data: (page) => page.items.isEmpty
                  ? SliverFillRemaining(
                      child: EmptyView(
                        icon: Icons.travel_explore,
                        title: filters.isEmpty ? 'New trips are coming soon' : 'No trips match your filters',
                        message: 'Tell us where you want to go and we\'ll plan it for you.',
                        action: FilledButton(onPressed: () => context.push('/plan-trip'), child: const Text('Plan a trip with us')),
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverList.separated(
                        itemCount: page.items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (_, i) => TripCard(
                          trip: page.items[i],
                          onTap: () => context.push('/trips/${page.items[i].id}'),
                        ),
                      ),
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  void _apply(TripFilters f) => ref.read(tripFiltersProvider.notifier).state = f;

  TripFilters _copy(TripFilters f, {String? search}) => TripFilters(
        search: search ?? f.search,
        category: f.category,
        province: f.province,
        area: f.area,
        maxPriceCents: f.maxPriceCents,
        from: f.from,
        to: f.to,
      );

  Future<void> _openFilters(TripFilters current) async {
    final result = await showModalBottomSheet<TripFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FilterSheet(initial: current),
    );
    if (result != null) _apply(result);
  }
}

class _SpecialsBanner extends StatefulWidget {
  const _SpecialsBanner({required this.specials});
  final List<Special> specials;

  @override
  State<_SpecialsBanner> createState() => _SpecialsBannerState();
}

class _SpecialsBannerState extends State<_SpecialsBanner> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(children: [
        SizedBox(
          height: 112,
          child: PageView.builder(
            controller: PageController(viewportFraction: 0.92),
            itemCount: widget.specials.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) {
              final s = widget.specials[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppColors.coral, borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    Text('${s.percentOff}%\nOFF',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.deepBlue, height: 1.1)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.deepBlue)),
                        if (s.description != null)
                          Text(s.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.deepBlue)),
                        Text('Until ${formatDate(s.endsAt)}', style: const TextStyle(fontSize: 12, color: AppColors.deepBlue)),
                      ]),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
        if (widget.specials.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < widget.specials.length; i++)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: i == _page ? AppColors.teal : AppColors.border),
                ),
            ]),
          ),
      ]),
    );
  }
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.initial});
  final TripFilters initial;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late String? _category = widget.initial.category;
  late String? _province = widget.initial.province;
  late String? _area = widget.initial.area;
  late double _maxPrice = (widget.initial.maxPriceCents ?? 2000000) / 100;
  late bool _priceSet = widget.initial.maxPriceCents != null;
  late DateTimeRange? _dates =
      widget.initial.from == null ? null : DateTimeRange(start: widget.initial.from!, end: widget.initial.to ?? widget.initial.from!);

  @override
  Widget build(BuildContext context) {
    final locations = ref.watch(departureLocationsProvider).valueOrNull ?? const <DepartureLocation>[];
    final areas = locations.where((l) => l.province == _province).expand((l) => l.areas).toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Filter trips', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          const Text('Type of trip', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in tripCategories)
              ChoiceChip(
                label: Text(titleCase(c)),
                selected: _category == c,
                onSelected: (s) => setState(() => _category = s ? c : null),
              ),
          ]),
          const SizedBox(height: 20),
          const Text('Departs from', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            value: _province,
            decoration: const InputDecoration(labelText: 'Province'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Any province')),
              for (final l in locations) DropdownMenuItem<String?>(value: l.province, child: Text(l.province)),
            ],
            onChanged: (v) => setState(() {
              _province = v;
              _area = null;
            }),
          ),
          if (areas.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              value: _area,
              decoration: const InputDecoration(labelText: 'Area / town'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Any area')),
                for (final a in areas) DropdownMenuItem<String?>(value: a, child: Text(a)),
              ],
              onChanged: (v) => setState(() => _area = v),
            ),
          ],
          const SizedBox(height: 20),
          Row(children: [
            const Expanded(child: Text('Maximum price per adult', style: TextStyle(fontWeight: FontWeight.w600))),
            Switch(value: _priceSet, onChanged: (v) => setState(() => _priceSet = v)),
          ]),
          if (_priceSet) ...[
            Slider(
              value: _maxPrice,
              min: 500,
              max: 20000,
              divisions: 39,
              label: randShort((_maxPrice * 100).round()),
              onChanged: (v) => setState(() => _maxPrice = v),
            ),
            Text('Up to ${randShort((_maxPrice * 100).round())}'),
          ],
          const SizedBox(height: 20),
          const Text('Travel dates', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range),
            label: Text(_dates == null ? 'Any dates' : '${formatDay(_dates!.start)} – ${formatDay(_dates!.end)}'),
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDateRangePicker(
                context: context,
                firstDate: now,
                lastDate: now.add(const Duration(days: 730)),
                initialDateRange: _dates,
              );
              if (picked != null) setState(() => _dates = picked);
            },
          ),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: OutlinedButton(onPressed: () => Navigator.pop(context, const TripFilters()), child: const Text('Clear')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  TripFilters(
                    search: widget.initial.search,
                    category: _category,
                    province: _province,
                    area: _area,
                    maxPriceCents: _priceSet ? (_maxPrice * 100).round() : null,
                    from: _dates?.start,
                    to: _dates?.end,
                  ),
                ),
                child: const Text('Show trips'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ============================ Trip details ============================

class TripDetailScreen extends ConsumerWidget {
  const TripDetailScreen({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(tripDetailProvider(tripId));
    return Scaffold(
      body: AsyncView(
        value: trip,
        onRetry: () => ref.invalidate(tripDetailProvider(tripId)),
        data: (t) => _TripDetailBody(trip: t),
      ),
    );
  }
}

class _TripDetailBody extends ConsumerWidget {
  const _TripDetailBody({required this.trip});
  final TripDetail trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(liveSeatsProvider(trip.id)).valueOrNull;
    final departures = [
      for (final d in trip.departures) live != null && live.containsKey(d.id) ? d.withSeatsBooked(live[d.id]!) : d,
    ];
    final pastTrips = ref.watch(tripPastTripsProvider(trip.id)).valueOrNull ?? const [];
    final reviews = ref.watch(tripReviewsProvider(trip.id)).valueOrNull ?? const [];
    final company = ref.watch(companyProvider).valueOrNull;
    final gallery = trip.gallery;

    return CustomScrollView(slivers: [
      SliverAppBar(
        pinned: true,
        expandedHeight: 280,
        flexibleSpace: FlexibleSpaceBar(
          background: gallery.isEmpty
              ? const NetImage(null)
              : PageView(children: [for (final url in gallery) NetImage(url)]),
        ),
      ),
      SliverToBoxAdapter(
        child: Constrained(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(trip.title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(trip.destination, style: const TextStyle(color: AppColors.secondaryText, fontSize: 16)),
              if (trip.tagline != null) ...[
                const SizedBox(height: 8),
                Text(trip.tagline!, style: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.teal)),
              ],
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (trip.averageRating != null)
                  Pill('${trip.averageRating!.toStringAsFixed(1)} ★ (${trip.reviewCount})', tone: PillTone.sand),
                if (trip.isCrossBorder) Pill('Cross-border · passport needed', icon: Icons.badge_outlined, tone: PillTone.sand),
                if (trip.isYouthCamp) Pill('Grade ${trip.minGrade}–${trip.maxGrade} learners', icon: Icons.school, tone: PillTone.sand),
                if (trip.isAdultsOnly) const Pill('Adults only (18+)', tone: PillTone.sand),
                for (final s in trip.specials) Pill('${s.percentOff}% off · ${s.name}', icon: Icons.local_offer, tone: PillTone.accent),
              ]),
              if (trip.isYouthCamp) ...[
                const SizedBox(height: 12),
                const SandBox(
                  child: Text('Booked by a parent or guardian. Learners are supervised and coordinated by adult professionals at all times.'),
                ),
              ],
              const SectionTitle("What's included"),
              WhatsIncludedSection(included: trip.included),
              if (trip.activities.isNotEmpty) ...[
                const SectionTitle('Activities'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final a in trip.activities) Pill(a, icon: Icons.hiking, tone: PillTone.success),
                ]),
              ],
              if (trip.description.isNotEmpty) ...[
                const SectionTitle('About this trip'),
                Text(trip.description, style: const TextStyle(height: 1.5)),
              ],
              if (trip.itinerary.isNotEmpty) ...[
                const SectionTitle('Day by day'),
                for (final day in trip.itinerary)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: AppColors.tealTint,
                      child: Text('${day.dayNumber}', style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w700)),
                    ),
                    title: Text(day.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    childrenPadding: const EdgeInsets.only(left: 56, bottom: 12),
                    expandedAlignment: Alignment.centerLeft,
                    children: [Text(day.description)],
                  ),
              ],
              const SectionTitle('Dates and prices'),
              if (departures.isEmpty)
                EmptyView(
                  icon: Icons.event_outlined,
                  title: 'No dates yet',
                  message: 'New dates are coming soon. Ask us to let you know.',
                  action: company?.whatsappLink == null
                      ? null
                      : OutlinedButton.icon(
                          icon: const Icon(Icons.chat_outlined),
                          label: const Text('Ask on WhatsApp'),
                          onPressed: () => launchUrl(Uri.parse(company!.whatsappLink!), mode: LaunchMode.externalApplication),
                        ),
                )
              else
                for (final d in departures)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DepartureCard(
                      departure: d,
                      onBook: () => context.push('/trips/${trip.id}/book?departure=${d.id}'),
                    ),
                  ),
              if (pastTrips.isNotEmpty) ...[
                const SectionTitle("We've done this trip before"),
                SizedBox(
                  height: 170,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: pastTrips.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, i) {
                      final p = pastTrips[i];
                      return InkWell(
                        onTap: () => context.push('/past-trips/${p.id}'),
                        child: SizedBox(
                          width: 200,
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            NetImage(p.coverUrl, height: 120, width: 200, radius: 12),
                            const SizedBox(height: 6),
                            Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text('${p.mediaCount} photos & videos', style: const TextStyle(fontSize: 12, color: AppColors.secondaryText)),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              ],
              if (reviews.isNotEmpty) ...[
                const SectionTitle('Reviews'),
                for (final r in reviews.take(5))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(backgroundColor: AppColors.warmSand, child: Text(r.customerFirstName[0])),
                    title: Text('${r.customerFirstName} · ${'★' * r.rating}'),
                    subtitle: r.comment == null ? null : Text(r.comment!),
                  ),
              ],
              const SizedBox(height: 32),
            ]),
          ),
        ),
      ),
    ]);
  }
}
