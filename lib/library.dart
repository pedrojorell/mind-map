import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'io/file_io.dart';
import 'models.dart';

/// Biblioteca local de mapas: guarda todos os documentos no armazenamento do
/// aplicativo (salvamento automático) e as preferências do usuário.
class Library extends ChangeNotifier {
  Library({SharedPreferences? prefs}) : _prefsOverride = prefs;

  // As chaves mantêm o prefixo antigo (PinealMap) para preservar os mapas
  // já salvos antes da mudança de nome para MapLong.
  static const _kIndex = 'pinealmap.index.v2';
  static const _kDocPrefix = 'pinealmap.doc.v2.';
  static const _kTheme = 'pinealmap.theme.v1';
  static const _kCheckUpdates = 'maplong.settings.checkUpdates';
  static const _kWelcomeSeen = 'maplong.settings.welcomeSeen';
  static const _kLegacyDocs = 'pinealmap.docs.v1';
  static const _kVersionsPrefix = 'pinealmap.versions.v1.';

  /// Máximo de versões guardadas por mapa.
  static int get maxVersions => canUseFilePaths ? 30 : 6;

  /// Intervalo mínimo entre versões automáticas.
  static const versionInterval = Duration(minutes: 10);

  /// Mapas na lixeira há mais tempo que isto são apagados de vez.
  static const trashDays = 30;

  final SharedPreferences? _prefsOverride;
  late SharedPreferences _prefs;

  final Map<String, MindMapDoc> _docs = {};
  final Map<String, Timer> _pendingSaves = {};

  bool isLoaded = false;
  ThemeMode themeMode = ThemeMode.dark;

  /// Verificar se há versão nova do MapLong ao abrir.
  bool checkUpdates = true;

  /// A tela de boas-vindas já foi mostrada.
  bool welcomeSeen = false;

  /// Estado do salvamento automático (para a barra de status).
  final saveState = ValueNotifier<SaveState>(SaveState.saved);

  /// Mensagem do último erro ao salvar (se houver).
  String? lastSaveError;

  /// Área de transferência interna (subárvore em JSON).
  Map<String, dynamic>? clipboard;

  /// Texto enviado à área de transferência do sistema na última cópia.
  String? clipboardText;

  List<MindMapDoc> get docsByRecent =>
      _docs.values.where((d) => d.deletedAt == null).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  List<MindMapDoc> get trash =>
      _docs.values.where((d) => d.deletedAt != null).toList()
        ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));

  /// Mapa ativo (fora da lixeira).
  MindMapDoc? doc(String id) {
    final d = _docs[id];
    return d == null || d.deletedAt != null ? null : d;
  }

  void toggleStar(String id) {
    final d = _docs[id];
    if (d == null) return;
    d.starred = !d.starred;
    _write(d);
    notifyListeners();
  }

  /// Envia para a lixeira (pode ser restaurado).
  Future<void> moveToTrash(String id) async {
    final d = _docs[id];
    if (d == null) return;
    _pendingSaves.remove(id)?.cancel();
    d.deletedAt = DateTime.now().millisecondsSinceEpoch;
    await _write(d);
    notifyListeners();
  }

  Future<void> restore(String id) async {
    final d = _docs[id];
    if (d == null) return;
    d.deletedAt = null;
    d.touch();
    await _write(d);
    notifyListeners();
  }

  Future<void> emptyTrash() async {
    for (final d in trash) {
      await delete(d.id);
    }
  }

  // ------------------------------------------------------------ versões

  /// Versões salvas de um mapa (mais recente primeiro): (quando, json).
  List<(int, String)> versions(String id) {
    final raw = _prefs.getStringList('$_kVersionsPrefix$id') ?? const [];
    final out = <(int, String)>[];
    for (final r in raw) {
      final i = r.indexOf('|');
      if (i < 0) continue;
      out.add((int.tryParse(r.substring(0, i)) ?? 0, r.substring(i + 1)));
    }
    out.sort((a, b) => b.$1.compareTo(a.$1));
    return out;
  }

  /// Guarda uma versão do mapa. Sem [force], só guarda se a última versão
  /// for mais antiga que [versionInterval] e o conteúdo tiver mudado.
  Future<bool> saveVersion(MindMapDoc d, {bool force = false}) async {
    final list = versions(d.id);
    final json = jsonEncode(d.toJson()..remove('filePath'));
    final now = DateTime.now().millisecondsSinceEpoch;
    if (list.isNotEmpty) {
      if (list.first.$2 == json) return false;
      if (!force && now - list.first.$1 < versionInterval.inMilliseconds) {
        return false;
      }
    }
    final next = [(now, json), ...list].take(maxVersions);
    await _prefs.setStringList('$_kVersionsPrefix${d.id}', [
      for (final v in next) '${v.$1}|${v.$2}',
    ]);
    return true;
  }

  Future<void> load() async {
    _prefs = _prefsOverride ?? await SharedPreferences.getInstance();

    themeMode = switch (_prefs.getString(_kTheme)) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    checkUpdates = _prefs.getBool(_kCheckUpdates) ?? true;
    welcomeSeen = _prefs.getBool(_kWelcomeSeen) ?? false;

    final ids = _prefs.getStringList(_kIndex) ?? const <String>[];
    for (final id in ids) {
      final raw = _prefs.getString('$_kDocPrefix$id');
      if (raw == null) continue;
      try {
        final d = MindMapDoc.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        _docs[d.id] = d;
      } catch (e) {
        debugPrint('MapLong: documento $id corrompido: $e');
      }
    }

    // Migra o formato antigo (todos os mapas numa única chave).
    final legacy = _prefs.getString(_kLegacyDocs);
    if (legacy != null) {
      try {
        for (final item in jsonDecode(legacy) as List<dynamic>) {
          final d = MindMapDoc.fromJson(Map<String, dynamic>.from(item));
          _docs.putIfAbsent(d.id, () => d);
          await _write(d);
        }
        await _writeIndex();
        await _prefs.remove(_kLegacyDocs);
      } catch (e) {
        debugPrint('MapLong: falha ao migrar dados antigos: $e');
      }
    }

    // Esvazia itens antigos da lixeira.
    final limit = DateTime.now()
        .subtract(const Duration(days: trashDays))
        .millisecondsSinceEpoch;
    for (final d in _docs.values.toList()) {
      if (d.deletedAt != null && d.deletedAt! < limit) await delete(d.id);
    }

    isLoaded = true;
    notifyListeners();
  }

  /// Tema efetivo agora (resolve "igual ao sistema").
  bool get isDark => switch (themeMode) {
    ThemeMode.dark => true,
    ThemeMode.light => false,
    ThemeMode.system =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark,
  };

  /// Alterna entre claro e escuro (a partir do tema que está na tela).
  void toggleTheme() => setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    _prefs.setString(_kTheme, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      ThemeMode.dark => 'dark',
    });
    notifyListeners();
  }

  void setCheckUpdates(bool on) {
    checkUpdates = on;
    _prefs.setBool(_kCheckUpdates, on);
    notifyListeners();
  }

  void markWelcomeSeen() {
    welcomeSeen = true;
    _prefs.setBool(_kWelcomeSeen, true);
  }

  /// Mostra a tela de boas-vindas de novo na próxima abertura.
  void resetWelcome() {
    welcomeSeen = false;
    _prefs.setBool(_kWelcomeSeen, false);
  }

  String uniqueName(String base) {
    final existing = _docs.values.map((e) => e.name.toLowerCase()).toSet();
    if (!existing.contains(base.toLowerCase())) return base;
    for (var i = 2; ; i++) {
      final c = '$base $i';
      if (!existing.contains(c.toLowerCase())) return c;
    }
  }

  MindMapDoc create({String? name}) {
    final d = MindMapDoc.blank(name: uniqueName(name ?? 'Novo mapa'));
    add(d);
    return d;
  }

  void add(MindMapDoc d) {
    _docs[d.id] = d;
    _write(d);
    _writeIndex();
    notifyListeners();
  }

  MindMapDoc duplicate(String id) {
    final src = _docs[id]!;
    final copy = MindMapDoc.fromJson(src.toJson())
      ..id = newId()
      ..name = uniqueName('${src.name} (cópia)')
      ..filePath = null
      ..touch();
    add(copy);
    return copy;
  }

  void rename(String id, String name) {
    final d = _docs[id];
    if (d == null || name.trim().isEmpty) return;
    d.name = name.trim();
    d.touch();
    saveNow(d);
    notifyListeners();
  }

  /// Apaga o mapa de vez (sem lixeira).
  Future<void> delete(String id) async {
    _pendingSaves.remove(id)?.cancel();
    _docs.remove(id);
    await _prefs.remove('$_kDocPrefix$id');
    await _prefs.remove('$_kVersionsPrefix$id');
    await _writeIndex();
    notifyListeners();
  }

  /// Adiciona um documento importado de arquivo. Se já existir um mapa com o
  /// mesmo id, mantém a versão mais recente.
  MindMapDoc importDoc(MindMapDoc d) {
    final existing = _docs[d.id];
    if (existing != null) {
      if (d.updatedAt >= existing.updatedAt) {
        d.filePath ??= existing.filePath;
        _docs[d.id] = d;
        saveNow(d);
        notifyListeners();
        return d;
      }
      existing.filePath ??= d.filePath;
      return existing;
    }
    add(d);
    return d;
  }

  /// Agenda o salvamento (com atraso curto para agrupar edições).
  void scheduleSave(MindMapDoc d) {
    _pendingSaves[d.id]?.cancel();
    saveState.value = SaveState.saving;
    _pendingSaves[d.id] = Timer(const Duration(milliseconds: 400), () {
      _pendingSaves.remove(d.id);
      _write(d);
    });
  }

  Future<void> saveNow(MindMapDoc d) async {
    _pendingSaves.remove(d.id)?.cancel();
    await _write(d);
  }

  Future<void> flush() async {
    final ids = _pendingSaves.keys.toList();
    for (final id in ids) {
      _pendingSaves.remove(id)?.cancel();
      final d = _docs[id];
      if (d != null) await _write(d);
    }
  }

  Future<void> _write(MindMapDoc d) async {
    if (!_docs.containsKey(d.id)) return;
    try {
      final ok = await _prefs.setString(
        '$_kDocPrefix${d.id}',
        jsonEncode(d.toJson()),
      );
      if (!ok) throw StateError('o armazenamento recusou a gravação');
      if (d.deletedAt == null) await saveVersion(d);
      lastSaveError = null;
      if (_pendingSaves.isEmpty) saveState.value = SaveState.saved;
    } catch (e) {
      // Ex.: armazenamento do navegador cheio. O mapa continua aberto.
      lastSaveError = '$e';
      saveState.value = SaveState.error;
      debugPrint('MapLong: falha ao salvar "${d.name}": $e');
    }
  }

  Future<void> _writeIndex() =>
      _prefs.setStringList(_kIndex, _docs.keys.toList());

  @override
  void dispose() {
    flush();
    saveState.dispose();
    super.dispose();
  }
}

/// Estado do salvamento automático.
enum SaveState { saved, saving, error }
