import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/channel_item.dart';
import '../models/video_item.dart';
import '../providers/app_provider.dart';
import '../utils/constants.dart';
import '../widgets/video_feed_sliver.dart';
import 'video_player_screen.dart';

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  /// Empty means "all channels".
  String _channelFilter = '';

  void _open(VideoItem video) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VideoPlayerScreen(video: video)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        final channels = provider.allowedChannels;

        if (channels.isEmpty && provider.regularVideos.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.subscriptions_outlined,
                    size: 72, color: AppColors.ytGrey),
                SizedBox(height: 16),
                Text('Каналов пока нет',
                    style: TextStyle(
                        color: AppColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w500)),
                SizedBox(height: 8),
                Text('Попроси родителей добавить каналы',
                    style: TextStyle(color: AppColors.ytGrey, fontSize: 14)),
              ],
            ),
          );
        }

        // Drop a filter whose channel is no longer allowed.
        if (_channelFilter.isNotEmpty &&
            !channels.any((c) => c.youtubeChannelId == _channelFilter)) {
          _channelFilter = '';
        }

        final videos = _channelFilter.isEmpty
            ? provider.regularVideos
            : provider.regularVideos
                .where((v) => v.channelId == _channelFilter)
                .toList();

        return CustomScrollView(
          slivers: [
            if (channels.isNotEmpty)
              SliverToBoxAdapter(child: _buildChannelRow(channels)),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  _channelFilter.isEmpty ? 'Новое' : 'Видео канала',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            if (videos.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text('У этого канала пока нет видео',
                        style:
                            TextStyle(color: AppColors.ytGrey, fontSize: 14)),
                  ),
                ),
              )
            else
              VideoFeedSliver(videos: videos, onTap: _open),
          ],
        );
      },
    );
  }

  Widget _buildChannelRow(List<ChannelItem> channels) {
    return Container(
      color: AppColors.ytDarkBg,
      child: Column(
        children: [
          SizedBox(
            height: 98,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              itemCount: channels.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildAvatar(
                    label: 'Все',
                    selected: _channelFilter.isEmpty,
                    onTap: () => setState(() => _channelFilter = ''),
                    icon: Icons.grid_view_rounded,
                  );
                }

                final channel = channels[index - 1];
                final selected = _channelFilter == channel.youtubeChannelId;
                return _buildAvatar(
                  label: channel.name,
                  avatarUrl: channel.avatarUrl,
                  selected: selected,
                  // These used to be plain Columns with no gesture handler, so
                  // tapping a channel did nothing whatsoever.
                  onTap: () => setState(() => _channelFilter =
                      selected ? '' : channel.youtubeChannelId),
                );
              },
            ),
          ),
          const Divider(height: 0.5),
        ],
      ),
    );
  }

  Widget _buildAvatar({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    String avatarUrl = '',
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.ytRed : Colors.transparent,
                  width: 2,
                ),
              ),
              child: CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.ytDarkSurface,
                backgroundImage: avatarUrl.isNotEmpty
                    ? CachedNetworkImageProvider(avatarUrl)
                    : null,
                child: avatarUrl.isNotEmpty
                    ? null
                    : (icon != null
                        ? Icon(icon, color: AppColors.white, size: 22)
                        : Text(
                            label.isNotEmpty ? label[0].toUpperCase() : '?',
                            style: const TextStyle(
                                color: AppColors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w500),
                          )),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 64,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? AppColors.white : AppColors.ytGrey,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
