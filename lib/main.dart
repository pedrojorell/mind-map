import 'package:flutter/material.dart';

import 'io/file_io.dart';
import 'library.dart';
import 'services/app_log.dart';
import 'widgets/brand.dart';
import 'screens/workspace_screen.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Erros inesperados vão para o registro em vez de fechar o app.
  AppLog.install();
  // Traz os mapas salvos quando o app ainda se chamava PinealMap.
  await migrateLegacyStorage();
  // Arquivos recebidos ao abrir o app (ex.: dois cliques num .maplong).
  runApp(
    MapLongApp(initialFiles: args.where((a) => !a.startsWith('-')).toList()),
  );
}

class MapLongApp extends StatefulWidget {
  const MapLongApp({super.key, this.library, this.initialFiles = const []});

  /// Permite injetar uma biblioteca (usado nos testes).
  final Library? library;

  /// Caminhos de arquivos para abrir assim que o app carregar.
  final List<String> initialFiles;

  @override
  State<MapLongApp> createState() => _MapLongAppState();
}

class _MapLongAppState extends State<MapLongApp> with WidgetsBindingObserver {
  late final Library library = widget.library ?? Library();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!library.isLoaded) library.load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Garante que nada fique pendente ao minimizar/fechar.
    if (state != AppLifecycleState.resumed) library.flush();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    library.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: kBrandSeed, brightness: b);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: b == Brightness.dark
          ? const Color(0xFF12131A)
          : const Color(0xFFF7F7FB),
      appBarTheme: AppBarTheme(
        backgroundColor: b == Brightness.dark
            ? const Color(0xFF181A23)
            : Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'MapLong',
        scaffoldMessengerKey: AppLog.messengerKey,
        themeMode: library.themeMode,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: library.isLoaded
            ? WorkspaceScreen(
                library: library,
                initialFiles: widget.initialFiles,
              )
            : const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
    );
  }
}
