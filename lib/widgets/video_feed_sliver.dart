import 'package:flutter/material.dart';

import '../models/video_item.dart';
import 'video_card.dart';

/// A list of videos that becomes a grid once there is room for it.
///
/// Shared by the home feed, the channels tab and search: the layout was
/// written for the home feed first, and the other two kept showing one
/// full-width card per row on a tablet.
class VideoFeedSliver extends StatelessWidget {
  final List<VideoItem> videos;
  final void Function(VideoItem video) onTap;

  const VideoFeedSliver({
    super.key,
    required this.videos,
    required this.onTap,
  });

  /// Column count comes from a target card width rather than a device check —
  /// a tablet in split screen is as narrow as a phone.
  static int columnsFor(double width) =>
      (width / 380).floor().clamp(1, 4);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = columnsFor(width);

    if (columns == 1) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) =>
              VideoCard(video: videos[index], onTap: () => onTap(videos[index])),
          childCount: videos.length,
        ),
      );
    }

    // Fix the tile height explicitly: thumbnail plus the text block below it.
    // Letting the grid derive an aspect ratio clips the title at some widths.
    final tileHeight = width / columns * 9 / 16 + 96;

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
              VideoCard(video: videos[index], onTap: () => onTap(videos[index])),
          childCount: videos.length,
        ),
      ),
    );
  }
}
