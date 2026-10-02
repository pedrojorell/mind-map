import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maplong/app_info.dart';
import 'package:maplong/library.dart';
import 'package:maplong/main.dart';
import 'package:maplong/models.dart';
import 'package:maplong/services/updates.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Library> _library() async {
  SharedPreferences.setMockInitialValues({});
  final lib = Library(prefs: await SharedPreferences.getInstance());
  await lib.load();
  return lib;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('versão do app igual à do pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*([0-9.]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(kAppVersion, version);
  });

  group('atualizações', () {
    test('compara versões', () {
      expect(compareVersions('2.1.0', '2.0.0'), greaterThan(0));
      expect(compareVersions('v2.0.0', '2.0.0'), 0);
      expect(compareVersions('2.0', '2.0.1'), lessThan(0));
      expect(compareVersions('10.0.0', '9.9.9'), greaterThan(0));
      expect(compareVersions('2.1.0-beta', '2.1.0'), 0);
    });

    MockClient release(String tag, {int status = 200}) => MockClient(
      (req) async => http.Response(
        jsonEncode({
          'tag_name': tag,
          'html_url': 'https://github.com/x/y/releases/tag/$tag',
          'body': 'Novidades',
          'assets': [
            {
              'name': 'MapLong-Setup-2.1.0.exe',
              'browser_download_url': 'https://x/MapLong-Setup-2.1.0.exe',
            },
          ],
        }),
        status,
      ),
    );

    test('avisa quando há versão nova, com link do instalador', () async {
      final info = await checkForUpdate(
        client: release('v2.1.0'),
        current: '2.0.0',
      );
      expect(info!.version, '2.1.0');
      expect(info.downloadUrl, endsWith('.exe'));
    });

    test('não avisa se já está atualizado ou sem internet', () async {
      expect(
        await checkForUpdate(client: release('v2.0.0'), current: '2.0.0'),
        isNull,
      );
      expect(
        await checkForUpdate(
          client: release('v9.0.0', status: 404),
          current: '2.0.0',
        ),
        isNull,
      );
      expect(
        await checkForUpdate(
          client: MockClient((_) => throw const SocketException('offline')),
          current: '2.0.0',
        ),
        isNull,
      );
    });
  });

  group('configurações', () {
    test('tema, atualizações e boas-vindas são lembrados', () async {
      final lib = await _library();
      expect(lib.welcomeSeen, isFalse);
      expect(lib.checkUpdates, isTrue);
      lib
        ..setThemeMode(ThemeMode.system)
        ..setCheckUpdates(false)
        ..markWelcomeSeen();

      final again = Library(prefs: await SharedPreferences.getInstance());
      await again.load();
      expect(again.themeMode, ThemeMode.system);
      expect(again.checkUpdates, isFalse);
      expect(again.welcomeSeen, isTrue);
    });

    test('estado do salvamento: salvando e depois salvo', () async {
      final lib = await _library();
      final doc = MindMapDoc.blank(name: 'x');
      lib.add(doc);
      lib.scheduleSave(doc);
      expect(lib.saveState.value, SaveState.saving);
      await lib.flush();
      expect(lib.saveState.value, SaveState.saved);
    });
  });

  testWidgets('boas-vindas aparecem só na primeira vez', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final lib = await _library();
    lib.setCheckUpdates(false);
    await tester.pumpWidget(MapLongApp(library: lib));
    await tester.pumpAndSettle();
    expect(find.text('Bem-vindo ao MapLong'), findsOneWidget);

    await tester.tap(find.text('Começar'));
    await tester.pumpAndSettle();
    expect(find.text('Bem-vindo ao MapLong'), findsNothing);
    expect(lib.welcomeSeen, isTrue);
  });

  testWidgets('telas de Configurações e Sobre abrem', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final lib = await _library();
    lib
      ..markWelcomeSeen()
      ..setCheckUpdates(false);
    await tester.pumpWidget(MapLongApp(library: lib));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Configurações'));
    await tester.pumpAndSettle();
    expect(find.text('Aparência'), findsOneWidget);
    await tester.tap(find.text('Escuro'));
    await tester.pumpAndSettle();
    expect(lib.themeMode, ThemeMode.dark);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sobre o MapLong'));
    await tester.pumpAndSettle();
    expect(find.text('Versão $kAppVersion'), findsOneWidget);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
  });
}
