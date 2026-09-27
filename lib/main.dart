import 'package:flutter/material.dart';

import 'library.dart';
import 'screens/workspace_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PinealMapApp());
}

class PinealMapApp extends StatefulWidget {
  const PinealMapApp({super.key, this.library});

  /// Permite injetar uma biblioteca (usado nos testes).
  final Library? library;

  @override
  State<PinealMapApp> createState() => _PinealMapAppState();
}

class _PinealMapAppState extends State<PinealMapApp>
    with WidgetsBindingObserver {
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
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7C4DFF),
      brightness: b,
    );
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
        title: 'PinealMap',
        themeMode: library.themeMode,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: library.isLoaded
            ? WorkspaceScreen(library: library)
            : const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
    );
  }
}
