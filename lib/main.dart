import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'providers/app_provider.dart';
import 'screens/main_shell.dart';
import 'utils/constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  timeago.setLocaleMessages('ru', timeago.RuMessages());
  timeago.setDefaultLocale('ru');

  // Portrait everywhere except fullscreen video. In this player version
  // "fullscreen" *is* landscape orientation, so leaving the app free to rotate
  // made the two fight: the picture flipped and snapped back, and the exit
  // button did nothing while the device was physically sideways.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.ytDarkBg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Local database only — the app must open instantly and work offline.
  final appProvider = AppProvider();
  await appProvider.init();

  // channels.json is read after the first frame, so a slow or missing network
  // never delays startup.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    appProvider.syncFromRemote();
  });

  runApp(
    ChangeNotifierProvider.value(
      value: appProvider,
      child: const KidTubeApp(),
    ),
  );
}

class KidTubeApp extends StatelessWidget {
  const KidTubeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KidTube',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const MainShell(),
    );
  }
}
