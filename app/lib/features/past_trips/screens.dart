import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/api/api_client.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import 'models.dart';

final pastTripsProvider = FutureProvider.autoDispose<Paged<PastTripSummary>>((ref) {
  return ref.watch(apiProvider).get('/api/past-trips', (d) => Paged.fromJson(d, PastTripSummary.fromJson), query: {'pageSize': 50});
});

final pastTripProvider = FutureProvider.autoDispose.family<PastTripDetail, String>((ref, id) {
  return ref.watch(apiProvider).get('/api/past-trips/$id', (d) => PastTripDetail.fromJson(asJson(d)));
});

class PastTripsScreen extends ConsumerWidget {
  const PastTripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(pastTripsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Our previous trips')),
      backgroundColor: AppColors.warmSand,
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(pastTripsProvider.future).then((_) {}),
        child: AsyncView(
          value: trips,
          onRetry: () => ref.invalidate(pastTripsProvider),
          data: (page) => page.items.isEmpty
              ? const EmptyView(icon: Icons.photo_library_outlined, title: 'Photos coming soon')
              : LayoutBuilder(builder: (context, c) {
                  final columns = c.maxWidth > 900 ? 3 : (c.maxWidth > 560 ? 2 : 1);
                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 4 / 3.4,
                    ),
                    itemCount: page.items.length,
                    itemBuilder: (_, i) => _AlbumCard(page.items[i]),
                  );
                }),
        ),
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard(this.p);
  final PastTripSummary p;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/past-trips/${p.id}'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Stack(fit: StackFit.expand, children: [
                NetImage(p.coverUrl),
                if (p.isFeatured) const Positioned(left: 10, top: 10, child: Pill('Featured', icon: Icons.star, tone: PillTone.accent)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.title, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${formatDateOnly(p.travelledOn)} · ${p.mediaCount} photos & videos',
                    style: const TextStyle(fontSize: 12, color: AppColors.secondaryText)),
              ]),
            ),
          ]),
        ),
      );
}

class PastTripDetailScreen extends ConsumerWidget {
  const PastTripDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(pastTripProvider(id));
    return Scaffold(
      appBar: AppBar(title: Text(trip.valueOrNull?.title ?? 'Previous trip')),
      body: AsyncView(
        value: trip,
        onRetry: () => ref.invalidate(pastTripProvider(id)),
        data: (t) => Constrained(
          maxWidth: 1000,
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text([
                    t.destination,
                    formatDateOnly(t.travelledOn),
                    if (t.travellerCount != null) '${t.travellerCount} travellers',
                  ].join(' · '), style: const TextStyle(color: AppColors.secondaryText)),
                  if (t.story != null && t.story!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(t.story!, style: const TextStyle(height: 1.5)),
                  ],
                  if (t.tripId != null && t.hasUpcomingTrip) ...[
                    const SizedBox(height: 16),
                    CtaButton(label: 'Book this trip', icon: Icons.event_available, onPressed: () => context.push('/trips/${t.tripId}')),
                  ],
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisSpacing: 6, crossAxisSpacing: 6),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final m = t.media[i];
                    return GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => MediaViewer(media: t.media, initialIndex: i),
                        fullscreenDialog: true,
                      )),
                      child: Stack(fit: StackFit.expand, children: [
                        NetImage(m.thumbnailUrl ?? (m.isVideo ? null : m.url), radius: 8),
                        if (m.isVideo) const Center(child: Icon(Icons.play_circle_fill, color: AppColors.white, size: 48)),
                      ]),
                    );
                  },
                  childCount: t.media.length,
                ),
              ),
            ),
            if (t.testimonials.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SectionTitle('What travellers said'),
                    for (final q in t.testimonials)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SandBox(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (q.rating != null) Text('★' * q.rating!, style: const TextStyle(color: AppColors.coral, fontSize: 18)),
                            Text('"${q.quote}"', style: const TextStyle(fontStyle: FontStyle.italic, height: 1.4)),
                            const SizedBox(height: 6),
                            Text('– ${q.customerName}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                  ]),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ]),
        ),
      ),
    );
  }
}

/// Full-screen swipe viewer: pinch to zoom photos, tap to play videos.
class MediaViewer extends StatefulWidget {
  const MediaViewer({super.key, required this.media, required this.initialIndex});
  final List<PastTripMedia> media;
  final int initialIndex;

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late final _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.media[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('${_index + 1} of ${widget.media.length}'),
      ),
      body: Column(children: [
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.media.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) {
              final m = widget.media[i];
              return m.isVideo
                  ? _VideoItem(url: m.url, key: ValueKey(m.id))
                  : InteractiveViewer(minScale: 1, maxScale: 4, child: NetImage(m.url, fit: BoxFit.contain));
            },
          ),
        ),
        if (current.caption != null && current.caption!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(current.caption!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
          ),
      ]),
    );
  }
}

class _VideoItem extends StatefulWidget {
  const _VideoItem({super.key, required this.url});
  final String url;

  @override
  State<_VideoItem> createState() => _VideoItemState();
}

class _VideoItemState extends State<_VideoItem> {
  late final VideoPlayerController _video = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _video.initialize().then((_) {
      if (mounted) setState(() => _ready = true);
    }).catchError((Object _) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _video.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const Center(child: Text("This video can't be played.", style: TextStyle(color: Colors.white)));
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return GestureDetector(
      onTap: () {
        if (_video.value.isPlaying) {
          _video.pause();
        } else {
          _video.play();
        }
        setState(() {});
      },
      child: Center(
        child: AspectRatio(
          aspectRatio: _video.value.aspectRatio,
          child: Stack(alignment: Alignment.center, children: [
            VideoPlayer(_video),
            if (!_video.value.isPlaying) const Icon(Icons.play_circle_fill, size: 72, color: Colors.white),
          ]),
        ),
      ),
    );
  }
}
