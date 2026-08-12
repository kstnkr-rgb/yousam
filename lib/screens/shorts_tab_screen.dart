import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/app_provider.dart';
import '../models/video_item.dart';
import '../services/newpipe_service.dart';
import '../utils/constants.dart';
import '../widgets/shorts_stream_player.dart';

class ShortsTabScreen extends StatefulWidget {
  /// Whether this is the tab currently on screen. The shell keeps every tab
  /// alive, so without this the player has no way of knowing it is hidden.
  final bool isActive;

  const ShortsTabScreen({super.key, this.isActive = true});

  @override
  State<ShortsTabScreen> createState() => _ShortsTabScreenState();
}

class _ShortsTabScreenState extends State<ShortsTabScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  late PageController _pageController;
  int _currentPage = 0;

  /// Players used to live in a map here and leaked until the tab closed. They
  /// now belong to the page widget, so scrolling one out of view releases it.
  bool _appResumed = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Switching away from the app must not leave a Short talking in the
  /// background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed == _appResumed) return;
    setState(() => _appResumed = resumed);
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        if (provider.shorts.isEmpty) {
          return Container(
            color: Colors.black,
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_circle_outline,
                      size: 72, color: AppColors.ytGrey),
                  SizedBox(height: 16),
                  Text('Shorts пока нет',
                      style: TextStyle(
                          color: AppColors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w500)),
                  SizedBox(height: 8),
                  Text('Попроси родителей добавить каналы',
                      style: TextStyle(
                          color: AppColors.ytGrey, fontSize: 14)),
                ],
              ),
            ),
          );
        }

        return Container(
          color: Colors.black,
          child: PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            onPageChanged: _onPageChanged,
            itemCount: provider.shorts.length,
            itemBuilder: (context, index) {
              final video = provider.shorts[index];
              return _ShortsPage(
                key: ValueKey(video.youtubeVideoId),
                video: video,
                isActive:
                    index == _currentPage && widget.isActive && _appResumed,
              );
            },
          ),
        );
      },
    );
  }
}

class _ShortsPage extends StatefulWidget {
  final VideoItem video;
  final bool isActive;

  const _ShortsPage({
    super.key,
    required this.video,
    required this.isActive,
  });

  @override
  State<_ShortsPage> createState() => _ShortsPageState();
}

class _ShortsPageState extends State<_ShortsPage> {
  final NewPipeService _newPipe = NewPipeService();

  VideoStreams? _streams;
  bool _resolved = false;

  /// Only created when stream extraction fails. It brings ads and is the one
  /// that hits YouTube's 150–153 embedding refusals, so it is a last resort.
  YoutubePlayerController? _embedded;

  @override
  void initState() {
    super.initState();
    _loadStreams();
  }

  Future<void> _loadStreams() async {
    final streams = await _newPipe.videoStreams(widget.video.youtubeVideoId);
    if (!mounted) return;

    final usable =
        (streams != null && streams.playable.isNotEmpty) ? streams : null;

    setState(() {
      _streams = usable;
      _resolved = true;
      if (usable == null) {
        _embedded = YoutubePlayerController(
          initialVideoId: widget.video.youtubeVideoId,
          flags: const YoutubePlayerFlags(
            autoPlay: false,
            mute: false,
            loop: true,
            hideControls: true,
            showLiveFullscreenButton: false,
            controlsVisibleAtStart: false,
          ),
        );
      }
    });
    _applyPlayback();
  }

  @override
  void didUpdateWidget(covariant _ShortsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) _applyPlayback();
  }

  /// Only the embedded player needs driving from here; the stream player
  /// follows its own isActive flag.
  void _applyPlayback() {
    final embedded = _embedded;
    if (embedded == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.isActive ? embedded.play() : embedded.pause();
    });
  }

  @override
  void dispose() {
    _embedded?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final controller = _embedded;
    if (controller == null) return;
    controller.value.isPlaying ? controller.pause() : controller.play();
    setState(() {});
  }

  Widget _buildPlayer() {
    if (!_resolved) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.ytRed),
      );
    }

    final streams = _streams;
    if (streams != null) {
      return ShortsStreamPlayer(streams: streams, isActive: widget.isActive);
    }

    return _buildEmbedded();
  }

  /// The embedded player plus the tap-to-pause and scrub controls it lacks.
  /// The stream player builds its own equivalents.
  Widget _buildEmbedded() {
    final controller = _embedded;
    if (controller == null) return const SizedBox.expand();

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: YoutubePlayer(
              controller: controller,
              showVideoProgressIndicator: false,
            ),
          ),
        ),
        Positioned.fill(
          bottom: 70,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _togglePlay,
            child: controller.value.isPlaying
                ? const SizedBox.expand()
                : const Center(
                    child: Icon(Icons.play_arrow,
                        size: 72, color: Color(0xCCFFFFFF)),
                  ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 54,
          child: ProgressBar(
            controller: controller,
            isExpanded: true,
            colors: const ProgressBarColors(
              playedColor: AppColors.ytRed,
              handleColor: AppColors.ytRed,
              bufferedColor: Color(0x55FFFFFF),
              backgroundColor: Color(0x33FFFFFF),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Black background
        Container(color: Colors.black),

        _buildPlayer(),

        // Right side action buttons (YouTube Shorts style)
        Positioned(
          right: 12,
          bottom: 100,
          child: Column(
            children: [
              // Like
              _ActionButton(
                icon: Icons.thumb_up_outlined,
                label: 'Нравится',
                onTap: () {},
              ),
              const SizedBox(height: 24),
              // Dislike
              _ActionButton(
                icon: Icons.thumb_down_outlined,
                label: 'Не нравится',
                onTap: () {},
              ),
              const SizedBox(height: 24),
              // Comment
              _ActionButton(
                icon: Icons.comment_outlined,
                label: '0',
                onTap: () {},
              ),
              const SizedBox(height: 24),
              // Share
              _ActionButton(
                icon: Icons.reply,
                label: 'Поделиться',
                isFlipped: true,
                onTap: () {},
              ),
              const SizedBox(height: 24),
              // Remix
              _ActionButton(
                icon: Icons.graphic_eq,
                label: 'Ремикс',
                onTap: () {},
              ),
              const SizedBox(height: 24),
              // Rotating music disc
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  border: Border.all(
                      color: AppColors.ytGrey.withValues(alpha: 0.5),
                      width: 2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: video.channelAvatarUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: video.channelAvatarUrl,
                          fit: BoxFit.cover)
                      : Container(
                          color: AppColors.ytDarkSurface,
                          child: const Icon(Icons.music_note,
                              color: AppColors.white, size: 16),
                        ),
                ),
              ),
            ],
          ),
        ),

        // Bottom info
        Positioned(
          left: 12,
          right: 68,
          bottom: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Channel + Subscribe
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.ytDarkSurface,
                    backgroundImage: video.channelAvatarUrl.isNotEmpty
                        ? CachedNetworkImageProvider(video.channelAvatarUrl)
                        : null,
                    child: video.channelAvatarUrl.isEmpty
                        ? Text(
                            video.channelName.isNotEmpty
                                ? video.channelName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '@${video.channelName}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Subscribe button
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.ytSubscribeBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Подписка',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Video title
              Text(
                video.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              // Audio info
              Row(
                children: [
                  const Icon(Icons.music_note, color: Colors.white, size: 12),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${video.channelName} \u00B7 Original audio',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Progress bar at very bottom
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            height: 2,
            color: Colors.white.withValues(alpha: 0.2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.3,
                child: Container(
                  color: AppColors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isFlipped;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isFlipped = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Transform(
            alignment: Alignment.center,
            transform: isFlipped
                ? Matrix4.diagonal3Values(-1, 1, 1)
                : Matrix4.identity(),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
