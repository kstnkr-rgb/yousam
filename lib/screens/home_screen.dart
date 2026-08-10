import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/video_item.dart';
import '../providers/app_provider.dart';
import '../utils/constants.dart';
import '../widgets/video_card.dart';
import '../widgets/shorts_card.dart';
import 'video_player_screen.dart';
import 'shorts_player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Empty means "Все". Otherwise the YouTube channel id being filtered on.
  String _channelFilter = '';

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        // The chips are the allowed channels themselves — the original app
        // shipped fake YouTube categories that filtered nothing.
        final channels = provider.allowedChannels;
        if (_channelFilter.isNotEmpty &&
            !channels.any((c) => c.youtubeChannelId == _channelFilter)) {
          _channelFilter = '';
        }

        final regular = _filter(provider.regularVideos);
        final shorts = _filter(provider.shorts);

        return RefreshIndicator(
          color: AppColors.ytRed,
          backgroundColor: AppColors.ytDarkSurface,
          onRefresh: () => provider.refreshEverything(),
          child: CustomScrollView(
            slivers: [
              if (channels.isNotEmpty)
                SliverToBoxAdapter(
                  child: Container(
                    color: AppColors.ytDarkBg,
                    height: 48,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: channels.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _chip('Все', _channelFilter.isEmpty,
                              () => setState(() => _channelFilter = ''));
                        }
                        final channel = channels[index - 1];
                        final selected =
                            _channelFilter == channel.youtubeChannelId;
                        return _chip(
                          channel.name,
                          selected,
                          () => setState(() => _channelFilter =
                              selected ? '' : channel.youtubeChannelId),
                        );
                      },
                    ),
                  ),
                ),

              if (provider.isLoading)
                const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.ytRed),
                  ),
                )
              else if (regular.isEmpty && shorts.isEmpty)
                SliverFillRemaining(child: _buildEmptyState(provider))
              else ...[
                if (shorts.isNotEmpty && regular.length <= 2)
                  SliverToBoxAdapter(child: _buildShortsShelf(shorts)),

                if (regular.isNotEmpty) ..._buildFeed(context, regular, shorts),
              ],
            ],
          ),
        );
      },
    );
  }

  /// One full-width card per row reads fine on a phone but turns into a wall
  /// of huge thumbnails on a tablet, so wide screens get a grid instead. The
  /// column count comes from a target card width rather than a device check —
  /// a split-screen tablet is as narrow as a phone.
  List<Widget> _buildFeed(
      BuildContext context, List<VideoItem> regular, List<VideoItem> shorts) {
    const targetCardWidth = 380.0;
    final width = MediaQuery.sizeOf(context).width;
    final columns = (width / targetCardWidth).floor().clamp(1, 4);

    // The Shorts shelf is full-bleed, so it sits between grids rather than
    // inside one. With few videos it has already been placed above.
    final headCount = regular.length > 2 ? 2 : regular.length;
    final head = regular.take(headCount).toList();
    final tail = regular.skip(headCount).toList();

    return [
      _sliverFor(head, columns, width),
      if (shorts.isNotEmpty && regular.length > 2)
        SliverToBoxAdapter(child: _buildShortsShelf(shorts)),
      if (tail.isNotEmpty) _sliverFor(tail, columns, width),
    ];
  }

  Widget _sliverFor(List<VideoItem> videos, int columns, double width) {
    if (columns == 1) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) =>
              VideoCard(video: videos[index], onTap: () => _open(videos[index])),
          childCount: videos.length,
        ),
      );
    }

    // Fix the tile height explicitly: thumbnail plus the text block below it.
    // Letting the grid guess an aspect ratio clips the title at some widths.
    final cardWidth = width / columns;
    final tileHeight = cardWidth * 9 / 16 + 96;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisExtent: tileHeight,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) =>
              VideoCard(video: videos[index], onTap: () => _open(videos[index])),
          childCount: videos.length,
        ),
      ),
    );
  }

  List<VideoItem> _filter(List<VideoItem> videos) {
    if (_channelFilter.isEmpty) return videos;
    return videos.where((v) => v.channelId == _channelFilter).toList();
  }

  void _open(VideoItem video) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => VideoPlayerScreen(video: video)),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.white : AppColors.ytChipBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.black : AppColors.white,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppProvider provider) {
    if (provider.isSyncing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.ytRed),
            const SizedBox(height: 16),
            Text(
              provider.syncStatus.isEmpty
                  ? 'Загружаем видео…'
                  : provider.syncStatus,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.ytGrey, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.play_circle_outline,
                size: 72, color: AppColors.ytGrey),
            const SizedBox(height: 16),
            const Text(
              'Видео пока нет',
              style: TextStyle(
                  color: AppColors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              _channelFilter.isNotEmpty
                  ? 'У этого канала пока нет загруженных видео'
                  : 'Попроси родителей добавить каналы',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.ytGrey, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShortsShelf(List<VideoItem> shorts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 4, color: AppColors.ytDarkSurface),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 26,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.ytRed, width: 2),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Icon(Icons.play_arrow,
                    size: 14, color: AppColors.ytRed),
              ),
              const SizedBox(width: 8),
              const Text(
                'Shorts',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 290,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: shorts.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SizedBox(
                  width: 160,
                  child: ShortsCard(
                    video: shorts[index],
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ShortsPlayerScreen(
                            shorts: shorts,
                            initialIndex: index,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
        Container(height: 4, color: AppColors.ytDarkSurface),
      ],
    );
  }
}
