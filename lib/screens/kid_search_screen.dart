import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/channel_item.dart';
import '../models/video_item.dart';
import '../providers/app_provider.dart';
import '../utils/constants.dart';
import '../widgets/video_card.dart';
import 'video_player_screen.dart';

/// The child's search.
///
/// Backed entirely by the local database, so it cannot surface anything from
/// outside the allowed channels — there is no code path from this screen to
/// YouTube search.
class KidSearchScreen extends StatefulWidget {
  const KidSearchScreen({super.key});

  @override
  State<KidSearchScreen> createState() => _KidSearchScreenState();
}

class _KidSearchScreenState extends State<KidSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  String _query = '';
  ChannelItem? _channel;
  List<VideoItem> _results = [];
  bool _busy = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() {}); // keeps the clear button in sync with the field
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _runQuery(value);
    });
  }

  Future<void> _runQuery(String value) async {
    final query = value.trim();
    setState(() {
      _query = query;
      _busy = true;
    });

    final provider = context.read<AppProvider>();
    final videos = query.isEmpty
        ? (_channel == null
            ? <VideoItem>[]
            : await provider.videosOfChannel(_channel!.youtubeChannelId))
        : await provider.searchLocal(query);

    if (!mounted) return;
    setState(() {
      _results = _channel == null
          ? videos
          : videos
              .where((v) => v.channelId == _channel!.youtubeChannelId)
              .toList();
      _busy = false;
    });
  }

  void _selectChannel(ChannelItem? channel) {
    setState(() => _channel = channel);
    _runQuery(_controller.text);
  }

  void _open(VideoItem video) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VideoPlayerScreen(video: video)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ytDarkBg,
      appBar: AppBar(
        backgroundColor: AppColors.ytDarkBg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.white),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.white, fontSize: 16),
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Найти видео',
            hintStyle: TextStyle(color: AppColors.ytGrey),
            border: InputBorder.none,
          ),
          onChanged: _onQueryChanged,
          onSubmitted: _runQuery,
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close, color: AppColors.ytGrey),
              onPressed: () {
                _controller.clear();
                _runQuery('');
              },
            ),
        ],
      ),
      body: Column(
        children: [
          _buildChannelFilter(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildChannelFilter() {
    final channels = context.watch<AppProvider>().allowedChannels;
    if (channels.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: channels.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _chip('Все каналы', _channel == null,
                () => _selectChannel(null));
          }
          final channel = channels[index - 1];
          return _chip(
            channel.name,
            _channel?.id == channel.id,
            () => _selectChannel(_channel?.id == channel.id ? null : channel),
          );
        },
      ),
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

  Widget _buildBody() {
    if (_busy) {
      return const Center(child: CircularProgressIndicator(color: AppColors.ytRed));
    }

    // Nothing typed and no channel picked: show what there is to explore.
    if (_query.isEmpty && _channel == null) {
      return _buildBrowse();
    }

    if (_results.isEmpty) {
      return _buildEmpty();
    }

    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final video = _results[index];
        return VideoCard(video: video, onTap: () => _open(video));
      },
    );
  }

  Widget _buildBrowse() {
    final provider = context.watch<AppProvider>();
    final channels = provider.allowedChannels;
    final fresh = provider.regularVideos.take(20).toList();

    if (channels.isEmpty && fresh.isEmpty) {
      return _buildEmpty(
        icon: Icons.subscriptions_outlined,
        title: 'Каналов пока нет',
        hint: 'Попроси родителей добавить каналы',
      );
    }

    return ListView(
      children: [
        if (channels.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Наши каналы',
                style: TextStyle(
                    color: AppColors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
          ),
          SizedBox(
            height: 108,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: channels.length,
              itemBuilder: (context, index) {
                final channel = channels[index];
                return GestureDetector(
                  onTap: () => _selectChannel(channel),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: AppColors.ytDarkSurface,
                          backgroundImage: channel.avatarUrl.isNotEmpty
                              ? CachedNetworkImageProvider(channel.avatarUrl)
                              : null,
                          child: channel.avatarUrl.isEmpty
                              ? Text(
                                  channel.name.isNotEmpty
                                      ? channel.name[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      color: AppColors.white, fontSize: 24),
                                )
                              : null,
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: 76,
                          child: Text(
                            channel.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: AppColors.ytGrey, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        if (fresh.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('Новое',
                style: TextStyle(
                    color: AppColors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
          ),
          ...fresh.map((video) =>
              VideoCard(video: video, onTap: () => _open(video))),
        ],
      ],
    );
  }

  Widget _buildEmpty({
    IconData icon = Icons.search_off,
    String title = 'Ничего не нашлось',
    String hint = 'Попробуй другое слово',
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: AppColors.ytGrey),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text(hint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.ytGrey, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
