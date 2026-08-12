import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/newpipe_service.dart';
import '../utils/constants.dart';

/// A single Short played from its raw stream.
///
/// Deliberately bare: no control bar, because the chrome would cover a video
/// that fills the screen. Tap toggles playback and a hairline bar at the
/// bottom scrubs.
///
/// The player belongs to this widget rather than to the tab, so scrolling a
/// Short out of view releases it — that is what keeps a long session from
/// running out of players.
class ShortsStreamPlayer extends StatefulWidget {
  final VideoStreams streams;
  final bool isActive;

  const ShortsStreamPlayer({
    super.key,
    required this.streams,
    required this.isActive,
  });

  @override
  State<ShortsStreamPlayer> createState() => _ShortsStreamPlayerState();
}

class _ShortsStreamPlayerState extends State<ShortsStreamPlayer> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final options = widget.streams.playable;
    if (options.isEmpty) return;

    // Shorts are small and watched briefly; the lowest rendition that still
    // looks sharp on a phone starts fastest and is least likely to stall.
    final option = options.lastWhere(
      (o) => o.height >= 480,
      orElse: () => options.first,
    );

    await _player.open(Media(option.url), play: false);
    if (option.videoOnly && widget.streams.audioUrl != null) {
      await _player.setAudioTrack(AudioTrack.uri(widget.streams.audioUrl!));
    }
    await _player.setPlaylistMode(PlaylistMode.single);
    if (mounted && widget.isActive) await _player.play();
  }

  @override
  void didUpdateWidget(covariant ShortsStreamPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) return;
    widget.isActive ? _player.play() : _player.pause();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _toggle() {
    _player.state.playing ? _player.pause() : _player.play();
  }

  void _seekToFraction(double fraction) {
    final total = _player.state.duration;
    if (total <= Duration.zero) return;
    _player.seek(total * fraction.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Video(
          controller: _controller,
          fit: BoxFit.contain,
          controls: NoVideoControls,
        ),

        // Tap target stops short of the bottom strip so the scrub bar and the
        // side buttons stay reachable, and stays translucent so vertical
        // swipes still reach the pager.
        Positioned.fill(
          bottom: 70,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _toggle,
            child: StreamBuilder<bool>(
              stream: _player.stream.playing,
              initialData: _player.state.playing,
              builder: (context, snapshot) => (snapshot.data ?? true)
                  ? const SizedBox.expand()
                  : const Center(
                      child: Icon(Icons.play_arrow,
                          size: 72, color: Color(0xCCFFFFFF)),
                    ),
            ),
          ),
        ),

        Positioned(
          left: 0,
          right: 0,
          bottom: 54,
          child: _buildScrubBar(),
        ),
      ],
    );
  }

  Widget _buildScrubBar() {
    return StreamBuilder<Duration>(
      stream: _player.stream.position,
      initialData: _player.state.position,
      builder: (context, snapshot) {
        final total = _player.state.duration;
        final position = snapshot.data ?? Duration.zero;
        final progress = total > Duration.zero
            ? position.inMilliseconds / total.inMilliseconds
            : 0.0;

        return LayoutBuilder(
          builder: (context, constraints) {
            void seekAt(double dx) =>
                _seekToFraction(dx / constraints.maxWidth);

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => seekAt(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => seekAt(d.localPosition.dx),
              child: SizedBox(
                height: 24,
                child: Center(
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor: const Color(0x44FFFFFF),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppColors.ytRed),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
