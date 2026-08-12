import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/newpipe_service.dart';
import '../utils/constants.dart';

/// Plays a YouTube video from its raw stream instead of embedding YouTube's
/// own player.
///
/// The embedded player decides the resolution itself and ignores any request
/// to change it, so quality could not be controlled at all. Here the
/// renditions are listed explicitly and the viewer picks one.
///
/// Above roughly 360p YouTube stops muxing audio into the video file, so the
/// chosen video track is paired with a separate audio track that the player
/// keeps in sync.
class StreamPlayer extends StatefulWidget {
  final VideoStreams streams;

  const StreamPlayer({super.key, required this.streams});

  @override
  State<StreamPlayer> createState() => _StreamPlayerState();
}

class _StreamPlayerState extends State<StreamPlayer> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  VideoStreamOption? _current;

  @override
  void initState() {
    super.initState();
    final options = widget.streams.playable;
    // Start at 720p or the closest below it: high enough to look sharp on a
    // tablet, low enough not to stall on a home connection.
    _current = options.firstWhere(
      (o) => o.height <= 720,
      orElse: () => options.last,
    );
    _open(_current!, autoplay: true);
  }

  Future<void> _open(VideoStreamOption option, {bool autoplay = false}) async {
    final position = _player.state.position;

    await _player.open(Media(option.url), play: false);
    if (option.videoOnly && widget.streams.audioUrl != null) {
      await _player.setAudioTrack(AudioTrack.uri(widget.streams.audioUrl!));
    }
    // Resume where the viewer was rather than restarting on a quality change.
    if (position > Duration.zero) await _player.seek(position);
    if (autoplay || position > Duration.zero) await _player.play();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _pickQuality() {
    final options = widget.streams.playable;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.ytDarkSurface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Качество',
                  style: TextStyle(
                      color: AppColors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ),
            for (final option in options)
              ListTile(
                title: Text(option.label,
                    style: const TextStyle(color: AppColors.white)),
                trailing: option.url == _current?.url
                    ? const Icon(Icons.check, color: AppColors.ytRed)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _current = option);
                  _open(option);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Video(
      controller: _controller,
      fit: BoxFit.contain,
      // Only the quality button is ours. Fullscreen belongs to the player's
      // own controls: it opens as a separate screen, so the back gesture
      // leaves it without any handling on our side. A second button of our own
      // sat in the opposite corner doing the same thing by a different route.
      controls: (state) => Stack(
        children: [
          AdaptiveVideoControls(state),
          Positioned(
            top: 4,
            right: 4,
            child: TextButton(
              onPressed: _pickQuality,
              child: Text(
                _current?.label ?? 'авто',
                style: const TextStyle(
                    color: AppColors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
