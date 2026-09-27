import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Biblioteca local de mapas: guarda todos os documentos no armazenamento do
/// aplicativo (salvamento automático) e as preferências do usuário.
class Library extends ChangeNotifier {
  Library({SharedPreferences? prefs}) : _prefsOverride = prefs;

  static const _kIndex = 'pinealmap.index.v2';
  static const _kDocPrefix = 'pinealmap.doc.v2.';
  static const _kTheme = 'pinealmap.theme.v1';
  static const _kLegacyDocs = 'pinealmap.docs.v1';

  final SharedPreferences? _prefsOverride;
  late SharedPreferences _prefs;

  final Map<String, MindMapDoc> _docs = {};
  final Map<String, Timer> _pendingSaves = {};

  bool isLoaded = false;
  ThemeMode themeMode = ThemeMode.dark;

  /// Área de transferência interna (subárvore em JSON).
  Map<String, dynamic>? clipboard;

  /// Texto enviado à área de transferência do sistema na última cópia.
  String? clipboardText;

  List<MindMapDoc> get docsByRecent =>
      _docs.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  MindMapDoc? doc(String id) => _docs[id];

  Future<void> load() async {
    _prefs = _prefsOverride ?? await SharedPreferences.getInstance();

    final theme = _prefs.getString(_kTheme);
    if (theme == 'light') themeMode = ThemeMode.light;

    final ids = _prefs.getStringList(_kIndex) ?? const <String>[];
    for (final id in ids) {
      final raw = _prefs.getString('$_kDocPrefix$id');
      if (raw == null) continue;
      try {
        final d = MindMapDoc.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        _docs[d.id] = d;
      } catch (e) {
        debugPrint('PinealMap: documento $id corrompido: $e');
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
        debugPrint('PinealMap: falha ao migrar dados antigos: $e');
      }
    }

    isLoaded = true;
    notifyListeners();
  }

  void toggleTheme() {
    themeMode = themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    _prefs.setString(_kTheme, themeMode == ThemeMode.light ? 'light' : 'dark');
    notifyListeners();
  }

  String uniqueName(String base) {
    final existing = _docs.values.map((e) => e.name.toLowerCase()).toSet();
    if (!existing.contains(base.toLowerCase())) return base;
    for (var i = 2;; i++) {
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

  Future<void> delete(String id) async {
    _pendingSaves.remove(id)?.cancel();
    _docs.remove(id);
    await _prefs.remove('$_kDocPrefix$id');
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
    await _prefs.setString('$_kDocPrefix${d.id}', jsonEncode(d.toJson()));
  }

  Future<void> _writeIndex() =>
      _prefs.setStringList(_kIndex, _docs.keys.toList());

  @override
  void dispose() {
    flush();
    super.dispose();
  }
}
