import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/video_item.dart';
import '../providers/app_provider.dart';
import '../services/newpipe_service.dart';
import '../utils/config.dart';
import '../utils/constants.dart';
import '../widgets/stream_player.dart';
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

  /// Created only if stream extraction fails. Building it up front would spin
  /// up a web view and start playing YouTube behind the stream player.
  YoutubePlayerController? _controller;
  final GlobalKey _playerKey = GlobalKey();
  List<VideoItem> _suggested = const [];

  /// Direct stream playback is preferred; the embedded YouTube player stays as
  /// the fallback for when extraction fails, which it will from time to time.
  final NewPipeService _newPipe = NewPipeService();
  VideoStreams? _streams;

  /// Streams that were extracted but judged too low-quality to prefer over the
  /// embedded player. Kept rather than discarded: if the embedded player then
  /// refuses the video — its owner disallows embedding, or YouTube will not
  /// verify the embedder, the 150–153 family of errors — 360p is still far
  /// better than a blank screen.
  VideoStreams? _lowQualityStreams;
  bool _streamsResolved = false;

  bool _titleExpanded = false;
  bool _isFullscreen = false;
  String? _seekHint;
  Timer? _seekHintTimer;

  @override
  void initState() {
    super.initState();
    _loadStreams();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_suggested.isEmpty) _prepareSuggestions();
  }

  @override
  void dispose() {
    _seekHintTimer?.cancel();
    _controller?.removeListener(_onEmbeddedPlayerChanged);
    _controller?.dispose();
    _releaseOrientation();
    super.dispose();
  }

  /// Switches to direct playback when the embedded player gives up.
  void _onEmbeddedPlayerChanged() {
    final controller = _controller;
    if (controller == null || !controller.value.hasError) return;

    developer.log('Embedded player failed with code '
        '${controller.value.errorCode}');

    final fallback = _lowQualityStreams;
    if (fallback == null) return; // nothing better to switch to

    controller.removeListener(_onEmbeddedPlayerChanged);
    setState(() {
      _controller = null;
      _streams = fallback;
      _lowQualityStreams = null; // one way only, never bounce back
    });
    // Disposing a controller from inside its own notification is asking for
    // trouble; let the frame finish first.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
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
    final controller = _controller;
    if (controller == null) return;

    final position = controller.value.position + offset;
    final total = controller.metadata.duration;
    var target = position < Duration.zero ? Duration.zero : position;
    if (total > Duration.zero && target > total) target = total;

    controller.seekTo(target);
    setState(() => _seekHint = offset.isNegative ? '−10 сек' : '+10 сек');
    _seekHintTimer?.cancel();
    _seekHintTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _seekHint = null);
    });
  }

  /// The player plus, for the embedded one only, double-tap seek zones. The
  /// stream player brings its own gestures and its own controller, so wrapping
  /// it would seek a player nobody is watching.
  Widget _playerArea() {
    final player = _buildPlayer();
    return _streams == null ? _buildSeekOverlay(player) : player;
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
  /// it — which would restart the video on every rotation.
  Widget _buildPlayer() {
    if (!_streamsResolved) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: CircularProgressIndicator(color: AppColors.ytRed),
          ),
        ),
      );
    }

    final streams = _streams;
    if (streams != null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: StreamPlayer(key: _playerKey, streams: streams),
      );
    }

    return _buildEmbeddedPlayer();
  }

  /// YouTube's own player in a web view. Only reached when stream extraction
  /// failed — it costs us quality control and the captions toggle, but it
  /// keeps working when extraction breaks.
  Widget _buildEmbeddedPlayer() {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();

    return YoutubePlayer(
      key: _playerKey,
      controller: controller,
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
            ? Center(child: _playerArea())
            : SafeArea(
                bottom: false,
                child: sideBySide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 7,
                            child: _playerArea(),
                          ),
                          Expanded(
                            flex: 3,
                            child: _buildDetails(),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          _playerArea(),
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
                  _buildTag('#samtube'),
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

  Future<void> _loadStreams() async {
    final streams = await _newPipe.videoStreams(widget.video.youtubeVideoId);
    if (!mounted) return;

    // playable is sorted best-first, so its head is the ceiling on offer.
    final best = (streams == null || streams.playable.isEmpty)
        ? 0
        : streams.playable.first.height;
    final usable = best >= kMinDirectStreamHeight ? streams : null;

    if (streams != null && usable == null) {
      developer.log('Direct streams top out at ${best}p — using the embedded '
          'player instead: ${streams.diagnostics}');
    }

    setState(() {
      _streams = usable;
      // Held in reserve: the embedded player refuses some videos outright, and
      // then even a 360p stream is worth having.
      _lowQualityStreams = usable == null ? streams : null;
      _streamsResolved = true;

      if (usable == null) {
        final controller = YoutubePlayerController(
          initialVideoId: widget.video.youtubeVideoId,
          flags: const YoutubePlayerFlags(
            autoPlay: true,
            mute: false,
            disableDragSeek: false,
            loop: false,
            // Was true, which forced subtitles on with no way to switch them
            // off: this player exposes captions as a startup flag only, not as
            // a control. Off matches what YouTube itself does by default.
            enableCaption: false,
            forceHD: false,
          ),
        )..addListener(_onEmbeddedPlayerChanged);
        _controller = controller;
      }
    });
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
