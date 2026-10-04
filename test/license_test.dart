import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplong/editor_controller.dart';
import 'package:maplong/library.dart';
import 'package:maplong/licensing/license.dart';
import 'package:maplong/main.dart';
import 'package:maplong/templates.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Códigos gerados pelo gerador em Node.js (licencas/) com uma chave só de
/// teste: garante que o app aceita exatamente o que o gerador produz.
final _fixture =
    jsonDecode(File('test/fixtures/licenca_teste.json').readAsStringSync())
        as Map<String, dynamic>;
final _testKey = _fixture['chavePublica'] as String;
String _code(String plan) =>
    (_fixture[plan] as Map<String, dynamic>)['codigo'] as String;

const _day = Duration(days: 1);

Future<Library> _library({
  Map<String, Object> values = const {},
  DateTime Function()? clock,
}) async {
  SharedPreferences.setMockInitialValues(values);
  final lib = Library(
    prefs: await SharedPreferences.getInstance(),
    clock: clock,
    licensePublicKey: _testKey,
  );
  await lib.load();
  lib
    ..markWelcomeSeen()
    ..setCheckUpdates(false);
  return lib;
}

/// Biblioteca com o teste grátis encerrado há [daysAgo] dias.
Future<Library> _expired({int daysAgo = 30}) => _library(
  values: {
    'maplong.license.trialStart': DateTime.now()
        .subtract(Duration(days: daysAgo))
        .millisecondsSinceEpoch,
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('código da licença', () {
    test('aceita os códigos do gerador', () async {
      final pro = await verifyLicense(_code('pro'), publicKey: _testKey);
      expect(pro.plan, LicensePlan.pro);
      expect(pro.email, 'cliente@exemplo.com');
      expect(pro.id, 'MP-123456789');
      expect(pro.issuedLabel, '04/10/2026');
      expect(pro.isOwner, isFalse);

      final owner = await verifyLicense(_code('dono'), publicKey: _testKey);
      expect(owner.plan, LicensePlan.owner);
      expect(owner.isOwner, isTrue);
    });

    test('aceita o código com espaços, quebras de linha e aspas', () async {
      final c = _code('pro');
      final pasted = ' "${c.substring(0, 40)}\n${c.substring(40)}" \r\n';
      final lic = await verifyLicense(pasted, publicKey: _testKey);
      expect(lic.code, c);
    });

    test('recusa códigos alterados ou incompletos', () async {
      final c = _code('pro');
      final body = c.substring(kLicensePrefix.length).split('.');
      final payload =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(body[0]))),
              )
              as Map<String, dynamic>;
      payload['p'] = 'dono';
      final forged =
          '$kLicensePrefix${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}.${body[1]}';

      Future<String> error(String code) async {
        try {
          await verifyLicense(code, publicKey: _testKey);
          return 'aceito';
        } on LicenseException catch (e) {
          return e.message;
        }
      }

      expect(await error(forged), contains('inválido'));
      expect(await error(c.substring(0, 60)), contains('incompleto'));
      expect(await error('ABC-123'), contains('MAPLONG-'));
      expect(await error(''), contains('Cole'));
      expect(await error('MAPLONG-a\$b.c'), contains('caracteres'));
    });

    test('o app só aceita a chave do dono (não a de teste)', () async {
      expect(
        () => verifyLicense(_code('dono')),
        throwsA(isA<LicenseException>()),
      );
    });

    test('Ed25519 segue a RFC 8032 (mesmo padrão do gerador)', () async {
      List<int> hex(String s) => [
        for (var i = 0; i < s.length; i += 2)
          int.parse(s.substring(i, i + 2), radix: 16),
      ];
      // Vetor de teste 1 da RFC 8032 (mensagem vazia).
      final ok = await Ed25519().verify(
        const [],
        signature: Signature(
          hex(
            'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555'
            'fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b',
          ),
          publicKey: SimplePublicKey(
            hex(
              'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
            ),
            type: KeyPairType.ed25519,
          ),
        ),
      );
      expect(ok, isTrue);
    });
  });

  group('teste grátis', () {
    test('começa com 7 dias e termina depois disso', () async {
      var now = DateTime(2026, 10, 4, 10);
      final lib = await _library(clock: () => now);
      expect(lib.trialDaysLeft, kTrialDays);
      expect(lib.readOnly, isFalse);

      now = now.add(const Duration(days: 6, hours: 12));
      expect(lib.trialDaysLeft, 1);
      expect(lib.readOnly, isFalse);

      now = now.add(_day);
      expect(lib.trialDaysLeft, 0);
      expect(lib.readOnly, isTrue);
    });

    test('atrasar o relógio não estende o teste', () async {
      var now = DateTime(2026, 10, 4);
      final first = await _library(clock: () => now);
      expect(first.trialDaysLeft, 7);

      // Abre o app 10 dias depois e depois volta o relógio.
      now = now.add(const Duration(days: 10));
      final later = Library(
        prefs: await SharedPreferences.getInstance(),
        clock: () => now,
        licensePublicKey: _testKey,
      );
      await later.load();
      expect(later.readOnly, isTrue);

      now = DateTime(2026, 10, 4);
      final rewound = Library(
        prefs: await SharedPreferences.getInstance(),
        clock: () => now,
        licensePublicKey: _testKey,
      );
      await rewound.load();
      expect(rewound.readOnly, isTrue);
    });

    test('a licença libera tudo e continua ativa ao reabrir', () async {
      final lib = await _expired();
      expect(lib.readOnly, isTrue);

      final lic = await lib.activateLicense(_code('pro'));
      expect(lic.email, 'cliente@exemplo.com');
      expect(lib.readOnly, isFalse);

      final again = Library(
        prefs: await SharedPreferences.getInstance(),
        licensePublicKey: _testKey,
      );
      await again.load();
      expect(again.isLicensed, isTrue);
      expect(again.license!.id, 'MP-123456789');

      await again.removeLicense();
      expect(again.readOnly, isTrue);
    });

    test('código inválido não é salvo', () async {
      final lib = await _expired();
      await expectLater(
        lib.activateLicense('MAPLONG-abc.def'),
        throwsA(isA<LicenseException>()),
      );
      expect(lib.isLicensed, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('maplong.license.code'), isNull);
    });
  });

  group('modo leitura', () {
    test('bloqueia edições, mas deixa recolher ramos', () async {
      // O mapa foi criado durante o teste grátis, que depois terminou.
      final trial = await _library();
      final d = docFromTemplate(
        'Antes',
        kTemplates.firstWhere((t) => t.title == 'Projeto'),
      );
      trial.add(d);
      await trial.saveNow(d);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'maplong.license.trialStart',
        DateTime.now()
            .subtract(const Duration(days: 30))
            .millisecondsSinceEpoch,
      );
      final locked = Library(prefs: prefs, licensePublicKey: _testKey);
      await locked.load();
      expect(locked.readOnly, isTrue);

      final ed = EditorController(library: locked, doc: locked.doc(d.id)!);
      var notices = 0;
      ed.onReadOnly = () => notices++;
      final before = jsonEncode(ed.doc.toJson());

      expect(ed.addChild(), isNull);
      ed.startEditing(ed.doc.rootId);
      expect(ed.editingId, isNull);
      ed.updateNode(ed.doc.rootId, (n) => n.text = 'Mudou');
      expect(ed.addFloating(Offset.zero), isEmpty);
      expect(ed.pasteOutline('a\nb'), isFalse);
      ed.rename('Outro nome');
      expect(jsonEncode(ed.doc.toJson()), before);
      expect(notices, greaterThanOrEqualTo(5));

      // Recolher/expandir só muda a visualização.
      final branch = ed.doc.root.childrenIds.first;
      ed.toggleCollapse(branch);
      expect(ed.doc.nodes[branch]!.collapsed, isTrue);

      // Com a licença, volta a editar.
      await locked.activateLicense(_code('pro'));
      expect(ed.addChild(), isNotNull);
      ed.dispose();
    });
  });

  group('telas', () {
    void bigWindow(WidgetTester tester) {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('teste encerrado: faixa de aviso e criação bloqueada', (
      tester,
    ) async {
      bigWindow(tester);
      final lib = await _expired();
      await tester.pumpWidget(MapLongApp(library: lib));
      await tester.pumpAndSettle();

      expect(find.textContaining('modo leitura'), findsWidgets);
      expect(find.text('Ativar licença'), findsWidgets);

      // "Novo mapa" abre a tela da licença em vez de criar o mapa.
      await tester.tap(find.text('Clássico'));
      await tester.pumpAndSettle();
      expect(lib.docsByRecent, isEmpty);
      expect(find.text('Licença do MapLong'), findsOneWidget);
      expect(find.text('O teste grátis terminou'), findsOneWidget);
      expect(
        find.textContaining(kLicensePrice, findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('ativa a licença pela tela e libera o app', (tester) async {
      bigWindow(tester);
      final lib = await _expired();
      await tester.pumpWidget(MapLongApp(library: lib));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('license-chip')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('license-code')),
        // Formato certo, assinatura falsa.
        'MAPLONG-${'A' * 10}.${'A' * 86}',
      );
      await tester.tap(find.byKey(const Key('license-activate')));
      await tester.pumpAndSettle();
      expect(find.textContaining('inválido'), findsOneWidget);
      expect(lib.isLicensed, isFalse);

      await tester.enterText(
        find.byKey(const Key('license-code')),
        _code('dono'),
      );
      await tester.tap(find.byKey(const Key('license-activate')));
      await tester.pumpAndSettle();
      expect(lib.isLicensed, isTrue);
      expect(find.text('Acesso de proprietário'), findsOneWidget);
      expect(find.text('dono@exemplo.com'), findsOneWidget);

      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('modo leitura'), findsNothing);
      expect(find.text('Proprietário'), findsOneWidget);

      await tester.tap(find.text('Clássico'));
      await tester.pumpAndSettle();
      expect(lib.docsByRecent, hasLength(1));
      await lib.flush();
    });

    testWidgets('durante o teste: aviso discreto com os dias restantes', (
      tester,
    ) async {
      bigWindow(tester);
      final lib = await _library();
      await tester.pumpWidget(MapLongApp(library: lib));
      await tester.pumpAndSettle();
      expect(find.text('Teste grátis · 7 dias'), findsOneWidget);
      expect(find.textContaining('modo leitura'), findsNothing);
    });
  });
}
