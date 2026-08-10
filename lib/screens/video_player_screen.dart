import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/video_item.dart';
import '../providers/app_provider.dart';
import '../utils/constants.dart';
import '../widgets/video_card.dart';

class VideoPlayerScreen extends StatefulWidget {
  final VideoItem video;

  const VideoPlayerScreen({super.key, required this.video});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  /// Enough to scroll through, few enough to build in one frame.
  static const int _maxSuggestions = 20;

  late YoutubePlayerController _controller;
  final GlobalKey _playerKey = GlobalKey();
  List<VideoItem> _suggested = const [];
  bool _titleExpanded = false;
  bool _isFullscreen = false;
  String? _seekHint;
  Timer? _seekHintTimer;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController(
      initialVideoId: widget.video.youtubeVideoId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        disableDragSeek: false,
        loop: false,
        // Was true, which forced subtitles on with no way to switch them off:
        // this player exposes captions as a startup flag only, not as a
        // control. Off matches what YouTube itself does by default.
        enableCaption: false,
        forceHD: false,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_suggested.isEmpty) _prepareSuggestions();
  }

  @override
  void dispose() {
    _seekHintTimer?.cancel();
    _controller.dispose();
    _releaseOrientation();
    super.dispose();
  }

  /// Stop dictating an orientation and put the system bars back.
  ///
  /// Every attempt to pin one made things worse somewhere: app-wide it
  /// letterboxed the tablet, screen-wide it letterboxed the video page. This
  /// player treats landscape as fullscreen, so the device's own orientation
  /// has to stay in charge.
  void _releaseOrientation() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  /// Double tap left/right to jump ten seconds, the way YouTube behaves.
  void _seekBy(Duration offset) {
    final position = _controller.value.position + offset;
    final total = _controller.metadata.duration;
    var target = position < Duration.zero ? Duration.zero : position;
    if (total > Duration.zero && target > total) target = total;

    _controller.seekTo(target);
    setState(() => _seekHint = offset.isNegative ? '−10 сек' : '+10 сек');
    _seekHintTimer?.cancel();
    _seekHintTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _seekHint = null);
    });
  }

  Widget _buildSeekOverlay(Widget player) {
    return Stack(
      alignment: Alignment.center,
      children: [
        player,
        // translucent so single taps still reach the player's own controls
        // Seek zones sit on the sides only. A double-tap recogniser has to
        // wait out the double-tap interval before releasing a single tap, so
        // anywhere it overlaps a button that button feels sluggish or misses
        // the press entirely — which is why the play/pause icon could be left
        // showing the wrong state. The middle column and the bottom control
        // bar are deliberately left uncovered, the same split YouTube uses.
        Positioned.fill(
          bottom: 56,
          child: Row(
            children: [
              Expanded(
                flex: 35,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: () => _seekBy(const Duration(seconds: -10)),
                ),
              ),
              const Expanded(flex: 30, child: SizedBox.expand()),
              Expanded(
                flex: 35,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: () => _seekBy(const Duration(seconds: 10)),
                ),
              ),
            ],
          ),
        ),
        if (_seekHint != null)
          IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _seekHint!,
                style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }

  /// The player widget itself, kept identical across every layout.
  ///
  /// The GlobalKey is what lets it move between the column, the side-by-side
  /// row and the fullscreen layout without Flutter tearing down and rebuilding
  /// the underlying web view — which would restart the video on every rotation.
  Widget _buildPlayer() {
    return YoutubePlayer(
      key: _playerKey,
      controller: _controller,
      showVideoProgressIndicator: true,
      progressIndicatorColor: AppColors.ytRed,
      progressColors: const ProgressBarColors(
        playedColor: AppColors.ytRed,
        handleColor: AppColors.ytRed,
        bufferedColor: Color(0x55FFFFFF),
        backgroundColor: Color(0x33FFFFFF),
      ),
      bottomActions: [
        const SizedBox(width: 8),
        CurrentPosition(),
        const SizedBox(width: 8),
        ProgressBar(
          isExpanded: true,
          colors: const ProgressBarColors(
            playedColor: AppColors.ytRed,
            handleColor: AppColors.ytRed,
            bufferedColor: Color(0x55FFFFFF),
            backgroundColor: Color(0x33FFFFFF),
          ),
        ),
        const SizedBox(width: 8),
        RemainingDuration(),
        // Our own button instead of the package's FullScreenButton: that one
        // toggles orientation, which is the behaviour we are deliberately
        // getting away from.
        IconButton(
          icon: Icon(
            _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
            color: AppColors.white,
          ),
          onPressed: _toggleFullscreen,
        ),
      ],
    );
  }

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Widget _buildDetails() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTitleSection(),
          const Divider(height: 0.5),
          _buildChannelSection(),
          const Divider(height: 0.5),
          _buildActionButtons(),
          const Divider(height: 0.5),
          _buildCommentsPreview(),
          const Divider(height: 0.5),
          _buildSuggestedVideos(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Side by side once the screen is both wide and wider than it is tall —
    // a phone in landscape is too short to give the video a useful height.
    final sideBySide = size.width >= 840 && size.width > size.height;

    return PopScope(
      // Back should leave fullscreen first, not the video.
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isFullscreen) _toggleFullscreen();
      },
      child: Scaffold(
        backgroundColor: AppColors.ytDarkBg,
        body: _isFullscreen
            ? Center(child: _buildSeekOverlay(_buildPlayer()))
            : SafeArea(
                bottom: false,
                child: sideBySide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 7,
                            child: _buildSeekOverlay(_buildPlayer()),
                          ),
                          Expanded(
                            flex: 3,
                            child: _buildDetails(),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          _buildSeekOverlay(_buildPlayer()),
                          Expanded(child: _buildDetails()),
                        ],
                      ),
              ),
      ),
    );
  }

  Widget _buildTitleSection() {
    return GestureDetector(
      onTap: () => setState(() => _titleExpanded = !_titleExpanded),
      child: Container(
        color: AppColors.ytDarkBg,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    widget.video.title,
                    maxLines: _titleExpanded ? 10 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Icon(
                    _titleExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.white,
                    size: 22,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${widget.video.viewCount} \u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440\u043E\u0432 \u00B7 ${timeago.format(widget.video.publishedAt, locale: 'ru')}',
              style: const TextStyle(
                color: AppColors.ytGrey,
                fontSize: 12,
              ),
            ),
            if (_titleExpanded) ...[
              const SizedBox(height: 12),
              // Tags
              Wrap(
                spacing: 6,
                children: [
                  _buildTag('#kidtube'),
                  _buildTag('#длядетей'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTag(String tag) {
    return Text(
      tag,
      style: const TextStyle(
        color: Color(0xFF3EA6FF),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildChannelSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.ytDarkSurface,
            child: Text(
              widget.video.channelName.isNotEmpty
                  ? widget.video.channelName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.video.channelName,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Subscribe button (YouTube style)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Подписка',
              style: TextStyle(
                color: Colors.black,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _buildActionChip(Icons.thumb_up_outlined, 'Нравится'),
          const SizedBox(width: 8),
          _buildActionChip(Icons.thumb_down_outlined, ''),
          const SizedBox(width: 8),
          _buildActionChip(Icons.bookmark_border, 'Сохранить'),
        ],
      ),
    );
  }

  Widget _buildActionChip(IconData icon, String label,
      {bool flipped = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.ytChipBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform(
            alignment: Alignment.center,
            transform: flipped
                ? Matrix4.diagonal3Values(-1, 1, 1)
                : Matrix4.identity(),
            child: Icon(icon, color: AppColors.white, size: 18),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCommentsPreview() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.ytDarkSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Комментарии',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Icon(Icons.lock_outline, color: AppColors.ytGrey, size: 14),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Комментарии отключены',
                  style: TextStyle(color: AppColors.ytGrey, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Builds the suggestion list once, when the screen opens.
  ///
  /// It used to sit in a Consumer and render every stored video into a Column.
  /// That was survivable with a few dozen videos in the database; once the
  /// library grew to thousands, opening a video meant constructing thousands
  /// of cards — each with a network image — in a single frame, on top of a
  /// rebuild for every provider notification. Playback stuttered because the
  /// UI thread never got a break, not because of the player.
  void _prepareSuggestions() {
    final provider = Provider.of<AppProvider>(context, listen: false);

    // regularVideos is already restricted to allowed channels, so nothing
    // outside the parent's list can appear here. Same channel first — that is
    // what "more like this" means to a kid.
    final sameChannel = <VideoItem>[];
    final others = <VideoItem>[];
    for (final video in provider.regularVideos) {
      if (video.youtubeVideoId == widget.video.youtubeVideoId) continue;
      if (video.channelId == widget.video.channelId) {
        sameChannel.add(video);
      } else if (others.length < _maxSuggestions) {
        others.add(video);
      }
      if (sameChannel.length >= _maxSuggestions) break;
    }

    _suggested = [...sameChannel, ...others].take(_maxSuggestions).toList();
  }

  Widget _buildSuggestedVideos() {
    if (_suggested.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Text(
            'Похожие видео',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ..._suggested.map((video) => VideoCard(
              video: video,
              compact: true,
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => VideoPlayerScreen(video: video),
                  ),
                );
              },
            )),
        const SizedBox(height: 24),
      ],
    );
  }
}
