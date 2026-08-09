import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/channel_item.dart';
import '../providers/app_provider.dart';
import '../utils/constants.dart';

class ManageChannelsScreen extends StatefulWidget {
  const ManageChannelsScreen({super.key});

  @override
  State<ManageChannelsScreen> createState() => _ManageChannelsScreenState();
}

class _ManageChannelsScreenState extends State<ManageChannelsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ytDarkBg,
      appBar: AppBar(
        backgroundColor: AppColors.ytDarkBg,
        title: const Text('Каналы',
            style: TextStyle(color: AppColors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.white),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.ytRed,
          labelColor: AppColors.white,
          unselectedLabelColor: AppColors.ytGrey,
          tabs: const [
            Tab(text: 'Разрешённые'),
            Tab(text: 'Заблокированные'),
          ],
        ),
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, child) {
          return TabBarView(
            controller: _tabController,
            children: [
              // Allowed channels
              _buildChannelList(
                provider.allowedChannels,
                isAllowed: true,
                provider: provider,
              ),
              // Blocked channels
              _buildChannelList(
                provider.blockedChannels,
                isAllowed: false,
                provider: provider,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildChannelList(
    List<ChannelItem> channels, {
    required bool isAllowed,
    required AppProvider provider,
  }) {
    if (channels.isEmpty) {
      return Center(
        child: Text(
          isAllowed ? 'Нет разрешённых каналов' : 'Нет заблокированных каналов',
          style: const TextStyle(color: AppColors.ytGrey, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channel = channels[index];
        return ListTile(
          leading: CircleAvatar(
            radius: 24,
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
                        color: AppColors.white, fontSize: 20),
                  )
                : null,
          ),
          title: Text(
            channel.name,
            style: const TextStyle(color: AppColors.white, fontSize: 15),
          ),
          subtitle: Text(
            // A channel with no sourceRef came from the "add temporarily"
            // dialog and the next remote sync will drop it. Say so here rather
            // than letting the parent discover it by restarting the app.
            isAllowed
                ? (channel.isRemote
                    ? 'Из channels.json'
                    : 'Временный — исчезнет при перезапуске')
                : 'Заблокирован',
            style: TextStyle(
              color: isAllowed
                  ? (channel.isRemote ? Colors.green : Colors.orange)
                  : AppColors.ytRed,
              fontSize: 12,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isAllowed)
                IconButton(
                  icon: const Icon(Icons.block, color: AppColors.ytRed, size: 22),
                  tooltip: 'Заблокировать',
                  onPressed: () => provider.blockChannel(channel),
                )
              else
                IconButton(
                  icon: const Icon(Icons.check_circle_outline,
                      color: Colors.green, size: 22),
                  tooltip: 'Разблокировать',
                  onPressed: () => provider.unblockChannel(channel),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.ytGrey, size: 22),
                tooltip: 'Удалить',
                onPressed: () => provider.removeChannel(channel.id),
              ),
            ],
          ),
        );
      },
    );
  }
}
