import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../utils/constants.dart';
import 'manage_videos_screen.dart';
import 'manage_channels_screen.dart';
import 'search_add_screen.dart';

class ParentDashboardScreen extends StatelessWidget {
  const ParentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ytDarkBg,
      appBar: AppBar(
        backgroundColor: AppColors.ytDarkBg,
        title: const Text('Родительский режим',
            style: TextStyle(color: AppColors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.white),
          onPressed: () {
            Provider.of<AppProvider>(context, listen: false).exitParentMode();
            Navigator.pop(context);
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: AppColors.white),
            onPressed: () => _showSettingsDialog(context),
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRemoteStatus(context, provider),
                const SizedBox(height: 20),

                // Stats
                Row(
                  children: [
                    _buildStatCard(
                      'Видео',
                      '${provider.allVideos.length}',
                      Icons.play_circle_outline,
                      AppColors.ytRed,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const ManageVideosScreen()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildStatCard(
                      'Shorts',
                      '${provider.shorts.length}',
                      Icons.flash_on,
                      Colors.orange,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const ManageVideosScreen()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildStatCard(
                      'Каналы',
                      '${provider.allowedChannels.length}',
                      Icons.people_outline,
                      Colors.blue,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const ManageChannelsScreen()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Quick actions
                const Text(
                  'Действия',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),

                _buildActionTile(
                  context,
                  Icons.add_circle_outline,
                  'Добавить видео по ссылке',
                  'Одно видео, независимо от списка каналов',
                  () => _showAddVideoDialog(context),
                ),
                _buildActionTile(
                  context,
                  Icons.search,
                  'Найти видео на YouTube',
                  'Поиск по всему YouTube и одобрение вручную',
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const SearchAddScreen()),
                  ),
                ),
                _buildActionTile(
                  context,
                  Icons.playlist_add,
                  'Добавить канал временно',
                  'До следующего запуска — постоянные каналы вписывайте '
                      'в channels.json',
                  () => _showAddChannelDialog(context),
                ),
                _buildActionTile(
                  context,
                  Icons.video_library,
                  'Список видео',
                  'Посмотреть и удалить видео',
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const ManageVideosScreen()),
                  ),
                ),
                _buildActionTile(
                  context,
                  Icons.sync,
                  'Проверить новые видео',
                  'Догрузить свежие ролики со всех каналов',
                  () => provider.syncAllChannels(),
                ),
                _buildActionTile(
                  context,
                  Icons.people,
                  'Список каналов',
                  'Разрешить или заблокировать канал',
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const ManageChannelsScreen()),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Status of the GitHub-hosted channel list: this is the control surface the
  /// parent actually manages the app from, so it goes above the stats.
  Widget _buildRemoteStatus(BuildContext context, AppProvider provider) {
    final error = provider.lastSyncError;
    final configured = provider.isRemoteConfigured;

    Color accent;
    IconData icon;
    String headline;

    if (provider.isSyncing) {
      accent = AppColors.ytGrey;
      icon = Icons.sync;
      headline = provider.syncStatus.isEmpty
          ? 'Синхронизация…'
          : provider.syncStatus;
    } else if (!configured) {
      accent = Colors.orange;
      icon = Icons.link_off;
      headline = 'Адрес channels.json не задан';
    } else if (error != null) {
      accent = AppColors.ytRed;
      icon = Icons.cloud_off;
      headline = 'Не удалось прочитать список: $error';
    } else {
      accent = Colors.green;
      icon = Icons.cloud_done;
      headline = 'Список каналов загружен';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.ytDarkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  headline,
                  style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Последняя удачная загрузка: ${_formatSyncTime(provider.lastSyncAt)}',
            style: const TextStyle(color: AppColors.ytGrey, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            provider.channelsUrl,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.ytLightGrey, fontSize: 11),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: provider.isSyncing
                    ? null
                    : () => provider.syncFromRemote(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Обновить'),
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
              ),
              TextButton.icon(
                onPressed: () => _showChannelsUrlDialog(context, provider),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Адрес файла'),
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.ytGrey,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatSyncTime(DateTime? time) {
    if (time == null) return 'ещё не было';
    final local = time.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  void _showChannelsUrlDialog(BuildContext context, AppProvider provider) {
    final controller = TextEditingController(text: provider.channelsUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.ytDarkSurface,
        title: const Text('Адрес channels.json',
            style: TextStyle(color: AppColors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Прямая ссылка на файл в репозитории (raw.githubusercontent.com):',
              style: TextStyle(color: AppColors.ytGrey, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              style: const TextStyle(color: AppColors.white, fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.ytDarkBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена',
                style: TextStyle(color: AppColors.ytGrey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await provider.setChannelsUrl(controller.text);
              await provider.syncFromRemote();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.ytRed),
            child: const Text('Сохранить',
                style: TextStyle(color: AppColors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color,
      {VoidCallback? onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.ytDarkSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(color: AppColors.ytGrey, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile(BuildContext context, IconData icon, String title,
      String subtitle, VoidCallback onTap) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.ytDarkSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.ytRed, size: 24),
      ),
      title: Text(title,
          style: const TextStyle(color: AppColors.white, fontSize: 15)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: AppColors.ytGrey, fontSize: 12)),
      trailing:
          const Icon(Icons.chevron_right, color: AppColors.ytGrey, size: 20),
      onTap: onTap,
    );
  }

  void _showAddVideoDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.ytDarkSurface,
        title: const Text('Добавить видео',
            style: TextStyle(color: AppColors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Вставьте ссылку на видео YouTube:',
              style: TextStyle(color: AppColors.ytGrey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: AppColors.white),
              decoration: InputDecoration(
                hintText: 'https://youtube.com/watch?v=...',
                hintStyle: const TextStyle(color: AppColors.ytGrey),
                filled: true,
                fillColor: AppColors.ytDarkBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: AppColors.ytGrey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final provider =
                  Provider.of<AppProvider>(context, listen: false);
              final video = await provider.addVideoByUrl(controller.text.trim());
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(video != null
                        ? 'Добавлено: ${video.title}'
                        : 'Не удалось добавить. Проверьте ссылку.'),
                    backgroundColor:
                        video != null ? Colors.green : AppColors.ytRed,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.ytRed),
            child: const Text('Добавить', style: TextStyle(color: AppColors.white)),
          ),
        ],
      ),
    );
  }

  void _showAddChannelDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.ytDarkSurface,
        title: const Text('Добавить канал временно',
            style: TextStyle(color: AppColors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ссылка на канал YouTube. Канал исчезнет при следующем запуске — '
              'источником правды остаётся channels.json.',
              style: TextStyle(color: AppColors.ytGrey, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: AppColors.white),
              decoration: InputDecoration(
                hintText: 'https://youtube.com/@channel',
                hintStyle: const TextStyle(color: AppColors.ytGrey),
                filled: true,
                fillColor: AppColors.ytDarkBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: AppColors.ytGrey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final provider =
                  Provider.of<AppProvider>(context, listen: false);
              final channel =
                  await provider.addChannelByUrl(controller.text.trim());
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(channel != null
                        ? 'Канал добавлен: ${channel.name}'
                        : 'Не удалось добавить канал. Проверьте ссылку.'),
                    backgroundColor:
                        channel != null ? Colors.green : AppColors.ytRed,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.ytRed),
            child: const Text('Добавить', style: TextStyle(color: AppColors.white)),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.ytDarkSurface,
        title: const Text('Сменить PIN',
            style: TextStyle(color: AppColors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Новый PIN из 4-6 цифр:',
              style: TextStyle(color: AppColors.ytGrey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.white, fontSize: 24, letterSpacing: 8),
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: AppColors.ytDarkBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: AppColors.ytGrey)),
          ),
          ElevatedButton(
            onPressed: () {
              final newPin = controller.text.trim();
              if (newPin.length >= 4) {
                Provider.of<AppProvider>(context, listen: false)
                    .setParentPin(newPin);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('PIN обновлён'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.ytRed),
            child:
                const Text('Сохранить', style: TextStyle(color: AppColors.white)),
          ),
        ],
      ),
    );
  }
}
