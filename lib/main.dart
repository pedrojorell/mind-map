import 'dart:convert';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vector_math/vector_math_64.dart' as vmath;

import 'platform_utils.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PinealMapApp());
}

/// ============================
///  APP + CONTROLLER
/// ============================

class PinealMapApp extends StatefulWidget {
  const PinealMapApp({super.key});

  @override
  State<PinealMapApp> createState() => _PinealMapAppState();
}

class _PinealMapAppState extends State<PinealMapApp> {
  late final MindMapController controller;

  @override
  void initState() {
    super.initState();
    controller = MindMapController()..load();
    controller.addListener(_onController);
  }

  void _onController() => setState(() {});

  @override
  void dispose() {
    controller.removeListener(_onController);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = controller.themeMode;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PinealMap',
      themeMode: themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF7C4DFF),
        textTheme: GoogleFonts.interTextTheme(),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF7C4DFF),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      ),
      home: controller.isLoaded
          ? HomeScreen(controller: controller)
          : const _SplashLoading(),
    );
  }
}

class _SplashLoading extends StatelessWidget {
  const _SplashLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class MindMapController extends ChangeNotifier {
  static const _kPrefsDocs = 'pinealmap.docs.v1';
  static const _kPrefsTheme = 'pinealmap.theme.v1';
  static const _kPrefsOpenTabs = 'pinealmap.openTabs.v1';
  static const _kPrefsActiveTab = 'pinealmap.activeTab.v1';

  final Map<String, MindMapDoc> _docs = {};
  final List<String> _openDocIds = [];
  String? _activeDocId;

  bool isLoaded = false;
  ThemeMode themeMode = ThemeMode.dark;

  // History per doc
  final Map<String, _History> _history = {};

  // Clipboard (node/subtree)
  Map<String, dynamic>? _clipboardSnapshot;

  List<MindMapDoc> get docsSorted {
    final list = _docs.values.toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  MindMapDoc? get activeDoc => _activeDocId == null ? null : _docs[_activeDocId!];
  String? get activeDocId => _activeDocId;

  List<String> get openDocIds => List.unmodifiable(_openDocIds);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    // Theme
    final themeRaw = prefs.getString(_kPrefsTheme);
    if (themeRaw == 'light') themeMode = ThemeMode.light;
    if (themeRaw == 'dark') themeMode = ThemeMode.dark;

    // Docs
    final raw = prefs.getString(_kPrefsDocs);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        for (final item in decoded) {
          final doc = MindMapDoc.fromJson(item as Map<String, dynamic>);
          _docs[doc.id] = doc;
          _history[doc.id] = _History.initial(doc);
        }
      } catch (_) {
        // ignore (start clean)
      }
    }

    // Tabs
    final openRaw = prefs.getString(_kPrefsOpenTabs);
    if (openRaw != null && openRaw.trim().isNotEmpty) {
      try {
        final decoded = (jsonDecode(openRaw) as List<dynamic>).cast<String>();
        for (final id in decoded) {
          if (_docs.containsKey(id)) _openDocIds.add(id);
        }
      } catch (_) {}
    }

    final active = prefs.getString(_kPrefsActiveTab);
    if (active != null && _docs.containsKey(active)) {
      _activeDocId = active;
      if (!_openDocIds.contains(active)) _openDocIds.add(active);
    } else if (_openDocIds.isNotEmpty) {
      _activeDocId = _openDocIds.first;
    }

    isLoaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kPrefsDocs,
      jsonEncode(_docs.values.map((e) => e.toJson()).toList()),
    );
    await prefs.setString(
        _kPrefsTheme, themeMode == ThemeMode.light ? 'light' : 'dark');
    await prefs.setString(_kPrefsOpenTabs, jsonEncode(_openDocIds));
    if (_activeDocId != null) {
      await prefs.setString(_kPrefsActiveTab, _activeDocId!);
    }
  }

  void toggleTheme() {
    themeMode = themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    _persist();
    notifyListeners();
  }

  MindMapDoc createNewDoc({String? name}) {
    final doc = MindMapDoc.template(name: name ?? _uniqueName('Novo mapa'));
    _docs[doc.id] = doc;
    _history[doc.id] = _History.initial(doc);
    _openDoc(doc.id);
    _persist();
    notifyListeners();
    return doc;
  }

  void deleteDoc(String docId) {
    _docs.remove(docId);
    _history.remove(docId);

    _openDocIds.remove(docId);
    if (_activeDocId == docId) {
      _activeDocId = _openDocIds.isNotEmpty ? _openDocIds.first : null;
    }
    _persist();
    notifyListeners();
  }

  void renameDoc(String docId, String newName) {
    final d = _docs[docId];
    if (d == null) return;
    d.name = newName.trim().isEmpty ? d.name : newName.trim();
    d.touch();
    _pushHistory(docId);
    _persist();
    notifyListeners();
  }

  void openDoc(String docId) {
    if (!_docs.containsKey(docId)) return;
    _openDoc(docId);
    _persist();
    notifyListeners();
  }

  void closeDoc(String docId) {
    _openDocIds.remove(docId);
    if (_activeDocId == docId) {
      _activeDocId = _openDocIds.isNotEmpty ? _openDocIds.first : null;
    }
    _persist();
    notifyListeners();
  }

  void setActiveDoc(String docId) {
    if (!_docs.containsKey(docId)) return;
    _activeDocId = docId;
    if (!_openDocIds.contains(docId)) _openDocIds.add(docId);
    _persist();
    notifyListeners();
  }

  void _openDoc(String docId) {
    if (!_openDocIds.contains(docId)) _openDocIds.add(docId);
    _activeDocId = docId;
  }

  String _uniqueName(String base) {
    final existing = _docs.values.map((e) => e.name.toLowerCase()).toSet();
    if (!existing.contains(base.toLowerCase())) return base;
    for (int i = 2; i < 9999; i++) {
      final candidate = '$base $i';
      if (!existing.contains(candidate.toLowerCase())) return candidate;
    }
    return '$base ${DateTime.now().millisecondsSinceEpoch}';
  }

  /// ======= Actions on nodes (mutate doc) =======

  void saveNow(String docId) {
    final d = _docs[docId];
    if (d == null) return;
    d.touch();
    _persist();
    notifyListeners();
  }

  void updateNodeText(String docId, String nodeId, String text) {
    final d = _docs[docId];
    if (d == null) return;
    final n = d.nodes[nodeId];
    if (n == null) return;
    n.text = text;
    d.touch();
    _pushHistory(docId);
    _persist();
    notifyListeners();
  }

  void updateNodeStyle(
    String docId,
    String nodeId, {
    String? branchColor,
    String? fillColor,
    String? borderColor,
    String? textColor,
    String? fontFamily,
    double? fontSize,
    double? borderWidth,
    String? borderStyle,
    String? shape,
  }) {
    final d = _docs[docId];
    if (d == null) return;
    final n = d.nodes[nodeId];
    if (n == null) return;
    if (branchColor != null) n.branchColor = branchColor;
    if (fillColor != null) n.fillColor = fillColor;
    if (borderColor != null) n.borderColor = borderColor;
    if (textColor != null) n.textColor = textColor;
    if (fontFamily != null) n.fontFamily = fontFamily;
    if (fontSize != null) n.fontSize = fontSize;
    if (borderWidth != null) n.borderWidth = borderWidth;
    if (borderStyle != null) n.borderStyle = borderStyle;
    if (shape != null) n.shape = shape;
    d.touch();
    _pushHistory(docId);
    _persist();
    notifyListeners();
  }

  void updateNodeLink(String docId, String nodeId, String? link) {
    final d = _docs[docId];
    if (d == null) return;
    final n = d.nodes[nodeId];
    if (n == null) return;
    n.link = (link == null || link.trim().isEmpty) ? null : link.trim();
    d.touch();
    _pushHistory(docId);
    _persist();
    notifyListeners();
  }

  void addAttachments(
      String docId, String nodeId, List<NodeAttachment> attachments) {
    final d = _docs[docId];
    if (d == null) return;
    final n = d.nodes[nodeId];
    if (n == null) return;
    n.attachments.addAll(attachments);
    d.touch();
    _pushHistory(docId);
    _persist();
    notifyListeners();
  }

  void removeAttachment(String docId, String nodeId, int index) {
    final d = _docs[docId];
    if (d == null) return;
    final n = d.nodes[nodeId];
    if (n == null) return;
    if (index < 0 || index >= n.attachments.length) return;
    n.attachments.removeAt(index);
    d.touch();
    _pushHistory(docId);
    _persist();
    notifyListeners();
  }

  void moveNode(String docId, String nodeId, Offset newPos) {
    final d = _docs[docId];
    if (d == null) return;
    final n = d.nodes[nodeId];
    if (n == null) return;
    n.pos = newPos;
    d.touch();
    // não empilha histórico a cada pixel; o editor chama "commitMove"
    _persist();
    notifyListeners();
  }

  void commitMove(String docId) {
    final d = _docs[docId];
    if (d == null) return;
    d.touch();
    _pushHistory(docId);
    _persist();
    notifyListeners();
  }

  String addTopic(String docId, String parentId) {
    final d = _docs[docId];
    if (d == null) return parentId;
    final parent = d.nodes[parentId];
    if (parent == null) return parentId;

    final id = _id();
    final n = MindMapNode(
      id: id,
      text: parentId == d.rootId ? 'Tópico Principal' : 'Subtópico',
      parentId: parentId,
      childrenIds: [],
      pos: parent.pos + const Offset(260, 0),
      branchColor: _autoColorForIndex(parent.childrenIds.length),
      fillColor: _autoColorForIndex(parent.childrenIds.length),
      borderColor: _autoColorForIndex(parent.childrenIds.length),
      textColor: '#FFFFFF',
      fontFamily: 'Inter',
      fontSize: 16,
      borderWidth: 1.4,
      borderStyle: 'solid',
      shape: parentId == d.rootId ? 'pill' : 'label',
      link: null,
      attachments: [],
      isFloating: false,
    );
    d.nodes[id] = n;
    parent.childrenIds.add(id);

    // Organiza verticalmente (bonitinho)
    _reflowChildren(d, parentId);

    d.touch();
    _pushHistory(docId);
    _persist();
    notifyListeners();
    return id;
  }

  String addSubtopic(String docId, String selectedId) {
    // Subtópico = filho do selecionado
    final d = _docs[docId];
    if (d == null) return selectedId;
    if (!d.nodes.containsKey(selectedId)) return selectedId;
    return addTopic(docId, selectedId);
  }

  String addFloating(String docId, Offset near) {
    final d = _docs[docId];
    if (d == null) return d?.rootId ?? '';
    final id = _id();
    d.nodes[id] = MindMapNode(
      id: id,
      text: 'Tópico Flutuante',
      parentId: null,
      childrenIds: [],
      pos: near,
      branchColor: '#7C4DFF',
      fillColor: '#1F2333',
      borderColor: '#7C4DFF',
      textColor: '#FFFFFF',
      fontFamily: 'Inter',
      fontSize: 16,
      borderWidth: 1.4,
      borderStyle: 'solid',
      shape: 'pill',
      link: null,
      attachments: [],
      isFloating: true,
    );
    d.touch();
    _pushHistory(docId);
    _persist();
    notifyListeners();
    return id;
  }

  void deleteNode(String docId, String nodeId) {
    final d = _docs[docId];
    if (d == null) return;
    if (nodeId == d.rootId) return;

    final node = d.nodes[nodeId];
    if (node == null) return;

    // Remove subtree
    final idsToDelete = <String>[];
    void collect(String id) {
      idsToDelete.add(id);
      final n = d.nodes[id];
      if (n == null) return;
      for (final c in n.childrenIds) collect(c);
    }

    collect(nodeId);

    // Remove from parent
    final parentId = node.parentId;
    if (parentId != null) {
      d.nodes[parentId]?.childrenIds.remove(nodeId);
      _reflowChildren(d, parentId);
    }

    for (final id in idsToDelete) {
      d.nodes.remove(id);
    }

    d.touch();
    _pushHistory(docId);
    _persist();
    notifyListeners();
  }

  void copyNode(String docId, String nodeId) {
    final d = _docs[docId];
    if (d == null) return;
    final node = d.nodes[nodeId];
    if (node == null) return;

    Map<String, dynamic> snapshotSubtree(String id) {
      final n = d.nodes[id]!;
      return {
        'node': n.toJson(),
        'children': n.childrenIds.map(snapshotSubtree).toList(),
      };
    }

    _clipboardSnapshot = snapshotSubtree(nodeId);
    notifyListeners();
  }

  void cutNode(String docId, String nodeId) {
    copyNode(docId, nodeId);
    deleteNode(docId, nodeId);
  }

  String? pasteToRoot(String docId) {
    final d = _docs[docId];
    if (d == null) return null;
    final snap = _clipboardSnapshot;
    if (snap == null) return null;

    // Build list of nodes from snapshot
    final oldToNew = <String, String>{};

    MindMapNode decodeNode(Map<String, dynamic> j, {required bool floating}) {
      final oldId = j['id'] as String;
      final newId = _id();
      oldToNew[oldId] = newId;

      final posMap = j['pos'] as Map<String, dynamic>;
      final oldPos = Offset(
        (posMap['dx'] as num).toDouble(),
        (posMap['dy'] as num).toDouble(),
      );

      return MindMapNode(
        id: newId,
        text: (j['text'] as String?) ?? 'Tópico',
        parentId: null, // set later
        childrenIds: [],
        pos: oldPos,
        branchColor: (j['branchColor'] as String?) ?? '#7C4DFF',
        fillColor: j['fillColor'] as String?,
        borderColor: (j['borderColor'] as String?) ?? j['branchColor'] as String?,
        textColor: j['textColor'] as String?,
        fontFamily: (j['fontFamily'] as String?) ?? 'Inter',
        fontSize: ((j['fontSize'] as num?) ?? 16).toDouble(),
        borderWidth: ((j['borderWidth'] as num?) ?? 1.4).toDouble(),
        borderStyle: (j['borderStyle'] as String?) ?? 'solid',
        shape: (j['shape'] as String?) ?? 'pill',
        link: j['link'] as String?,
        attachments: ((j['attachments'] as List<dynamic>?) ?? [])
            .map((e) => NodeAttachment.fromJson(e as Map<String, dynamic>))
            .toList(),
        isFloating: floating,
      );
    }

    void build(Map<String, dynamic> tree, String? newParentId) {
      final nodeJson = (tree['node'] as Map<String, dynamic>);
      final newNode = decodeNode(nodeJson, floating: newParentId == null);
      newNode.parentId = newParentId;
      d.nodes[newNode.id] = newNode;

      final children =
          (tree['children'] as List<dynamic>).cast<Map<String, dynamic>>();
      for (final c in children) {
        build(c, newNode.id);
        // after build, link
      }
    }

    // Paste as child of root (como você pediu)
    // Primeiro cria o nó raiz do paste (sem filhos), depois filhos.
    final tree = snap;
    final nodeJson = (tree['node'] as Map<String, dynamic>);
    final pastedRoot = decodeNode(nodeJson, floating: false);

    pastedRoot.parentId = d.rootId;
    d.nodes[pastedRoot.id] = pastedRoot;
    d.nodes[d.rootId]!.childrenIds.add(pastedRoot.id);

    // Offset pra não colar em cima
    final rootPos = d.nodes[d.rootId]!.pos;
    pastedRoot.pos = rootPos +
        Offset(260, 40.0 * (d.nodes[d.rootId]!.childrenIds.length));

    void buildChildren(
        Map<String, dynamic> treeNode, String newParentId, Offset delta) {
      final children =
          (treeNode['children'] as List<dynamic>).cast<Map<String, dynamic>>();
      for (final c in children) {
        final cJson = (c['node'] as Map<String, dynamic>);
        final newChild = decodeNode(cJson, floating: false);
        newChild.parentId = newParentId;

        // reposiciona relativo ao root colado
        final oldPosMap = cJson['pos'] as Map<String, dynamic>;
        final oldPos = Offset(
          (oldPosMap['dx'] as num).toDouble(),
          (oldPosMap['dy'] as num).toDouble(),
        );
        newChild.pos = oldPos + delta;

        d.nodes[newChild.id] = newChild;
        d.nodes[newParentId]!.childrenIds.add(newChild.id);

        buildChildren(c, newChild.id, delta);
      }
    }

    // delta = (pos novo root - pos antigo root)
    final oldRootPosMap = nodeJson['pos'] as Map<String, dynamic>;
    final oldRootPos = Offset(
      (oldRootPosMap['dx'] as num).toDouble(),
      (oldRootPosMap['dy'] as num).toDouble(),
    );
    final delta = pastedRoot.pos - oldRootPos;

    buildChildren(tree, pastedRoot.id, delta);

    _reflowChildren(d, d.rootId);

    d.touch();
    _pushHistory(docId);
    _persist();
    notifyListeners();
    return pastedRoot.id;
  }

  void _reflowChildren(MindMapDoc d, String parentId) {
    final parent = d.nodes[parentId];
    if (parent == null) return;
    final ids = parent.childrenIds;
    if (ids.isEmpty) return;

    // espaçamento vertical
    const gapY = 90.0;
    final startY = parent.pos.dy - (gapY * (ids.length - 1) / 2.0);

    for (int i = 0; i < ids.length; i++) {
      final n = d.nodes[ids[i]];
      if (n == null) continue;
      final x = parent.pos.dx + 320;
      final y = startY + (gapY * i);
      n.pos = Offset(x, y);
    }
  }

  void undo(String docId) {
    final h = _history[docId];
    final d = _docs[docId];
    if (h == null || d == null) return;
    final restored = h.undo();
    if (restored == null) return;
    _docs[docId] = restored;
    _persist();
    notifyListeners();
  }

  void redo(String docId) {
    final h = _history[docId];
    final d = _docs[docId];
    if (h == null || d == null) return;
    final restored = h.redo();
    if (restored == null) return;
    _docs[docId] = restored;
    _persist();
    notifyListeners();
  }

  void _pushHistory(String docId) {
    final d = _docs[docId];
    final h = _history[docId];
    if (d == null || h == null) return;
    h.push(d);
  }

  static String _id() => DateTime.now().microsecondsSinceEpoch.toString();

  static String _autoColorForIndex(int i) {
    const colors = [
      '#FF5252', // red
      '#FFB300', // amber
      '#00C853', // green
      '#2979FF', // blue
      '#7C4DFF', // purple
      '#00B8D4', // cyan
    ];
    return colors[i % colors.length];
  }

  void updateConnectorStyle(
    String docId, {
    String? connectorStyle,
    double? connectorWidth,
  }) {
    final d = _docs[docId];
    if (d == null) return;
    if (connectorStyle != null) d.connectorStyle = connectorStyle;
    if (connectorWidth != null) d.connectorWidth = connectorWidth;
    d.touch();
    _pushHistory(docId);
    _persist();
    notifyListeners();
  }
}

class _History {
  _History(this.stack, this.index);

  final List<String> stack; // json strings
  int index;

  static _History initial(MindMapDoc d) {
    return _History([jsonEncode(d.toJson())], 0);
  }

  void push(MindMapDoc d) {
    final encoded = jsonEncode(d.toJson());
    // se você fez undo e depois mudou, corta o "futuro"
    if (index < stack.length - 1) {
      stack.removeRange(index + 1, stack.length);
    }
    stack.add(encoded);
    index = stack.length - 1;

    // limita tamanho
    const limit = 80;
    if (stack.length > limit) {
      final drop = stack.length - limit;
      stack.removeRange(0, drop);
      index -= drop;
      index = max(index, 0);
    }
  }

  MindMapDoc? undo() {
    if (index <= 0) return null;
    index--;
    return MindMapDoc.fromJson(
        jsonDecode(stack[index]) as Map<String, dynamic>);
  }

  MindMapDoc? redo() {
    if (index >= stack.length - 1) return null;
    index++;
    return MindMapDoc.fromJson(
        jsonDecode(stack[index]) as Map<String, dynamic>);
  }
}

/// ============================
///  MODELS
/// ============================

class MindMapDoc {
  MindMapDoc({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.rootId,
    required this.nodes,
    required this.connectorStyle,
    required this.connectorWidth,
  });

  String id;
  String name;
  int createdAt;
  int updatedAt;
  String rootId;
  Map<String, MindMapNode> nodes;
  String connectorStyle;
  double connectorWidth;

  void touch() => updatedAt = DateTime.now().millisecondsSinceEpoch;

  static MindMapDoc template({required String name}) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final rootId = 'root_$id';

    final root = MindMapNode(
      id: rootId,
      text: 'Ideia Principal',
      parentId: null,
      childrenIds: [],
      pos: const Offset(0, 0),
      branchColor: '#7C4DFF',
      fillColor: '#1F2333',
      borderColor: '#7C4DFF',
      textColor: '#FFFFFF',
      fontFamily: 'Inter',
      fontSize: 20,
      borderWidth: 1.6,
      borderStyle: 'solid',
      shape: 'pill',
      link: null,
      attachments: [],
      isFloating: false,
    );

    final doc = MindMapDoc(
      id: id,
      name: name,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      rootId: rootId,
      nodes: {rootId: root},
      connectorStyle: 'curved',
      connectorWidth: 3,
    );

    // 3 tópicos principais
    for (int i = 0; i < 3; i++) {
      final childId = 'n_${id}_$i';
      final child = MindMapNode(
        id: childId,
        text: 'Tópico Principal',
        parentId: rootId,
        childrenIds: [],
        pos: Offset(320, (i - 1) * 90.0),
        branchColor: MindMapController._autoColorForIndex(i),
        fillColor: MindMapController._autoColorForIndex(i),
        borderColor: MindMapController._autoColorForIndex(i),
        textColor: '#FFFFFF',
        fontFamily: 'Inter',
        fontSize: 16,
        borderWidth: 1.4,
        borderStyle: 'solid',
        shape: 'pill',
        link: null,
        attachments: [],
        isFloating: false,
      );
      doc.nodes[childId] = child;
      root.childrenIds.add(childId);
    }

    return doc;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'rootId': rootId,
        'nodes': nodes.map((k, v) => MapEntry(k, v.toJson())),
        'connectorStyle': connectorStyle,
        'connectorWidth': connectorWidth,
      };

  static MindMapDoc fromJson(Map<String, dynamic> j) {
    final nodesMap = (j['nodes'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, MindMapNode.fromJson(v as Map<String, dynamic>)),
    );
    return MindMapDoc(
      id: j['id'] as String,
      name: j['name'] as String,
      createdAt: (j['createdAt'] as num).toInt(),
      updatedAt: (j['updatedAt'] as num).toInt(),
      rootId: j['rootId'] as String,
      nodes: nodesMap,
      connectorStyle: (j['connectorStyle'] as String?) ?? 'curved',
      connectorWidth: ((j['connectorWidth'] as num?) ?? 3).toDouble(),
    );
  }
}

class MindMapNode {
  MindMapNode({
    required this.id,
    required this.text,
    required this.parentId,
    required this.childrenIds,
    required this.pos,
    required this.branchColor,
    required this.fillColor,
    required this.borderColor,
    required this.textColor,
    required this.fontFamily,
    required this.fontSize,
    required this.borderWidth,
    required this.borderStyle,
    required this.shape,
    required this.link,
    required this.attachments,
    required this.isFloating,
  });

  String id;
  String text;
  String? parentId;
  List<String> childrenIds;
  Offset pos;

  String branchColor; // hex string
  String? fillColor;
  String? borderColor;
  String? textColor;
  String fontFamily; // Google font family name
  double fontSize;
  double borderWidth;
  String borderStyle; // solid | dashed
  String shape; // pill | rounded | rect | circle | label

  String? link;
  List<NodeAttachment> attachments;

  bool isFloating;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'parentId': parentId,
        'childrenIds': childrenIds,
        'pos': {'dx': pos.dx, 'dy': pos.dy},
        'branchColor': branchColor,
        'fillColor': fillColor,
        'borderColor': borderColor,
        'textColor': textColor,
        'fontFamily': fontFamily,
        'fontSize': fontSize,
        'borderWidth': borderWidth,
        'borderStyle': borderStyle,
        'shape': shape,
        'link': link,
        'attachments': attachments.map((e) => e.toJson()).toList(),
        'isFloating': isFloating,
      };

  static MindMapNode fromJson(Map<String, dynamic> j) {
    final posMap = j['pos'] as Map<String, dynamic>;
    return MindMapNode(
      id: j['id'] as String,
      text: (j['text'] as String?) ?? '',
      parentId: j['parentId'] as String?,
      childrenIds: ((j['childrenIds'] as List<dynamic>?) ?? []).cast<String>(),
      pos: Offset(
        (posMap['dx'] as num).toDouble(),
        (posMap['dy'] as num).toDouble(),
      ),
      branchColor: (j['branchColor'] as String?) ?? '#7C4DFF',
      fillColor: j['fillColor'] as String?,
      borderColor: (j['borderColor'] as String?) ?? j['branchColor'] as String?,
      textColor: j['textColor'] as String?,
      fontFamily: (j['fontFamily'] as String?) ?? 'Inter',
      fontSize: ((j['fontSize'] as num?) ?? 16).toDouble(),
      borderWidth: ((j['borderWidth'] as num?) ?? 1.4).toDouble(),
      borderStyle: (j['borderStyle'] as String?) ?? 'solid',
      shape: (j['shape'] as String?) ?? 'pill',
      link: j['link'] as String?,
      attachments: ((j['attachments'] as List<dynamic>?) ?? [])
          .map((e) => NodeAttachment.fromJson(e as Map<String, dynamic>))
          .toList(),
      isFloating: (j['isFloating'] as bool?) ?? false,
    );
  }
}

class NodeAttachment {
  NodeAttachment({required this.name, required this.path});

  final String name;
  final String path;

  Map<String, dynamic> toJson() => {'name': name, 'path': path};

  static NodeAttachment fromJson(Map<String, dynamic> j) {
    return NodeAttachment(
      name: (j['name'] as String?) ?? 'arquivo',
      path: (j['path'] as String?) ?? '',
    );
  }
}

/// ============================
///  HOME SCREEN (WORKBENCH)
/// ============================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final MindMapController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isSidebarCollapsed = false;

  Future<void> _openTemplatePicker(BuildContext context) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Novo mapa mental'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('Escolha um modelo para começar:'),
              SizedBox(height: 12),
              _TemplatePreviewCard(
                title: 'Mapa clássico',
                subtitle: 'Ideia principal + 3 tópicos',
                style: 'classic',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop('classic'),
              child: const Text('Criar')),
        ],
      ),
    );

    if (choice == null) return;
    final doc = widget.controller.createNewDoc(name: null);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EditorShell(controller: widget.controller, startDocId: doc.id),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final docs = widget.controller.docsSorted;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            SizedBox(width: 8),
            PineconeLogo(size: 20),
            SizedBox(width: 10),
            Text('PinealMap'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: widget.controller.themeMode == ThemeMode.dark
                ? 'Modo branco'
                : 'Modo escuro',
            onPressed: widget.controller.toggleTheme,
            icon: Icon(widget.controller.themeMode == ThemeMode.dark
                ? Icons.light_mode
                : Icons.dark_mode),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          // Sidebar simples (parecido com referência)
          Container(
            width: _isSidebarCollapsed ? 72 : 220,
            decoration: BoxDecoration(
              border:
                  Border(right: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: _isSidebarCollapsed
                          ? 'Expandir'
                          : 'Minimizar',
                      icon: Icon(_isSidebarCollapsed
                          ? Icons.chevron_right
                          : Icons.chevron_left),
                      onPressed: () => setState(
                          () => _isSidebarCollapsed = !_isSidebarCollapsed),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      _openTemplatePicker(context);
                    },
                    icon: const Icon(Icons.add),
                    label: Text(_isSidebarCollapsed ? '' : 'Criar'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: docs.isEmpty
                        ? null
                        : () {
                            // abre o primeiro (alfabético)
                            final doc = docs.first;
                            widget.controller.openDoc(doc.id);
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => EditorShell(
                                  controller: widget.controller, startDocId: doc.id),
                            ));
                          },
                    icon: const Icon(Icons.folder_open),
                    label: Text(_isSidebarCollapsed ? '' : 'Abrir'),
                  ),
                  const SizedBox(height: 14),
                  const Divider(),
                  const SizedBox(height: 8),
                  _SideItem(
                    icon: Icons.dashboard,
                    text: 'Workbench',
                    selected: true,
                    onTap: () {},
                    collapsed: _isSidebarCollapsed,
                  ),
                  _SideItem(
                    icon: Icons.image_outlined,
                    text: 'Galeria',
                    onTap: () {},
                    collapsed: _isSidebarCollapsed,
                  ),
                  _SideItem(
                    icon: Icons.group_outlined,
                    text: 'Espaço da equipe',
                    onTap: () {},
                    collapsed: _isSidebarCollapsed,
                  ),
                  const Spacer(),
                  _SideItem(
                    icon: Icons.settings_outlined,
                    text: 'Opções',
                    onTap: () {},
                    collapsed: _isSidebarCollapsed,
                  ),
                ],
              ),
            ),
          ),

          // Conteúdo
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tile "Novo mapa mental" em cima, central-esquerda
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      _NewMindmapTile(onTap: () {
                        _openTemplatePicker(context);
                      }),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text('Documentos salvos (A–Z)',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Expanded(
                    child: docs.isEmpty
                        ? const Center(
                            child:
                                Text('Nenhum mapa salvo ainda. Clique em “Criar”.'))
                        : ListView.separated(
                            itemCount: docs.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final d = docs[i];
                              return ListTile(
                                leading: const Icon(Icons.account_tree_outlined),
                                title: Text(d.name),
                                subtitle: Text(
                                    'Atualizado: ${DateTime.fromMillisecondsSinceEpoch(d.updatedAt)}'),
                                onTap: () {
                                  controller.openDoc(d.id);
                                  Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => EditorShell(
                                        controller: widget.controller, startDocId: d.id),
                                  ));
                                },
                                trailing: IconButton(
                                  tooltip: 'Excluir',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: const Text('Excluir mapa?'),
                                        content: Text(
                                            'Tem certeza que deseja excluir “${d.name}”?'),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text('Cancelar')),
                                          FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: const Text('Excluir')),
                                        ],
                                      ),
                                    );
                                    if (ok == true) widget.controller.deleteDoc(d.id);
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem(
      {required this.icon,
      required this.text,
      required this.onTap,
      this.selected = false,
      this.collapsed = false});

  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final bool selected;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: selected ? cs.primary : null),
            if (!collapsed) ...[
              const SizedBox(width: 10),
              Expanded(child: Text(text)),
            ],
          ],
        ),
      ),
    );
  }
}

class _NewMindmapTile extends StatelessWidget {
  const _NewMindmapTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 260,
        height: 150,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Center(
          child: Icon(Icons.add, size: 42, color: c.primary),
        ),
      ),
    );
  }
}

class _TemplatePreviewCard extends StatelessWidget {
  const _TemplatePreviewCard({
    required this.title,
    required this.subtitle,
    required this.style,
  });

  final String title;
  final String subtitle;
  final String style;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: CustomPaint(
              painter: _TemplatePreviewPainter(style: style),
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplatePreviewPainter extends CustomPainter {
  _TemplatePreviewPainter({required this.style});
  final String style;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.25, size.height * 0.5);
    final topicX = size.width * 0.65;
    final colors = [
      const Color(0xFFFF5252),
      const Color(0xFFFFB300),
      const Color(0xFF00C853),
    ];

    final basePaint = Paint()
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 3; i++) {
      final y = size.height * (0.25 + i * 0.25);
      basePaint.color = colors[i];
      canvas.drawPath(
        Path()
          ..moveTo(center.dx + 60, center.dy)
          ..cubicTo(
              center.dx + 120, center.dy, topicX - 10, y, topicX, y),
        basePaint,
      );
    }

    final rootPaint = Paint()
      ..color = const Color(0xFF1F2333)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 120, height: 40),
        const Radius.circular(20),
      ),
      rootPaint,
    );

    for (int i = 0; i < 3; i++) {
      final y = size.height * (0.25 + i * 0.25);
      final topicPaint = Paint()..color = colors[i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(topicX, y), width: 100, height: 34),
          const Radius.circular(16),
        ),
        topicPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TemplatePreviewPainter oldDelegate) =>
      oldDelegate.style != style;
}

/// ============================
///  EDITOR SHELL (TABS + TOOLBAR)
/// ============================

class EditorShell extends StatefulWidget {
  const EditorShell({super.key, required this.controller, required this.startDocId});
  final MindMapController controller;
  final String startDocId;

  @override
  State<EditorShell> createState() => _EditorShellState();
}

class _EditorShellState extends State<EditorShell>
    with SingleTickerProviderStateMixin {
  late final TabController _ribbonController;

  @override
  void initState() {
    super.initState();
    widget.controller.openDoc(widget.startDocId);
    widget.controller.setActiveDoc(widget.startDocId);
    _ribbonController = TabController(length: 4, vsync: this);
    _ribbonController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ribbonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final active = c.activeDocId;

    if (active == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('PinealMap'),
        ),
        body: const Center(child: Text('Nenhum documento aberto.')),
      );
    }

    final doc = c.activeDoc!;
    final themeName = c.themeMode == ThemeMode.dark ? 'Preto' : 'Branco';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const PineconeLogo(size: 18),
            const SizedBox(width: 10),
            Text(doc.name, overflow: TextOverflow.ellipsis),
          ],
        ),
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Renomear',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final name = await _promptText(
                context,
                title: 'Renomear documento',
                initial: doc.name,
                hint: 'Nome do mapa',
              );
              if (name != null) c.renameDoc(doc.id, name);
            },
          ),
          IconButton(
            tooltip: 'Modo claro/escuro',
            onPressed: c.toggleTheme,
            icon: Icon(c.themeMode == ThemeMode.dark
                ? Icons.light_mode
                : Icons.dark_mode),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(126),
          child: Column(
            children: [
              _RibbonTabs(controller: _ribbonController),
              _TabsRow(controller: c),
              _TopToolbar(
                controller: c,
                docId: doc.id,
                ribbonIndex: _ribbonController.index,
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('Tema: $themeName',
                    style: Theme.of(context).textTheme.labelSmall),
              ),
            ],
          ),
        ),
      ),
      body: MindMapEditorPage(
        key: ValueKey(active), // ✅ CORRIGE “um mapa alterando o outro”
        controller: c,
        docId: active,
      ),
    );
  }
}

class _TabsRow extends StatelessWidget {
  const _TabsRow({required this.controller});
  final MindMapController controller;

  @override
  Widget build(BuildContext context) {
    final open = controller.openDocIds;
    final active = controller.activeDocId;

    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          const SizedBox(width: 10),
          for (final id in open)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _TabChip(
                title: controller.activeDocId == id
                    ? controller.activeDoc!.name
                    : controller.docsSorted
                        .firstWhere((d) => d.id == id)
                        .name,
                active: id == active,
                onTap: () => controller.setActiveDoc(id),
                onClose: () => controller.closeDoc(id),
              ),
            ),
          _TabChip(
            title: '+ Novo',
            active: false,
            onTap: () => controller.createNewDoc(name: null),
            onClose: null,
          ),
          const SizedBox(width: 10),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.title,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final String title;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: active ? cs.primary.withOpacity(0.18) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, overflow: TextOverflow.ellipsis),
              if (onClose != null) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: onClose,
                  child: const Icon(Icons.close, size: 16),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RibbonTabs extends StatelessWidget {
  const _RibbonTabs({required this.controller});
  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: controller,
      labelColor: Theme.of(context).colorScheme.primary,
      unselectedLabelColor: Theme.of(context).textTheme.bodyMedium?.color,
      indicatorColor: Theme.of(context).colorScheme.primary,
      tabs: const [
        Tab(text: 'Iniciar'),
        Tab(text: 'Inserir'),
        Tab(text: 'Formatar'),
        Tab(text: 'Exibir'),
      ],
    );
  }
}

class _TopToolbar extends StatelessWidget {
  const _TopToolbar(
      {required this.controller,
      required this.docId,
      required this.ribbonIndex});
  final MindMapController controller;
  final String docId;
  final int ribbonIndex;

  @override
  Widget build(BuildContext context) {
    final editor = MindMapEditorPage.of(context);

    List<Widget> buttons;
    if (ribbonIndex == 1) {
      buttons = [
        _ToolButton(
          text: 'Tópico',
          icon: Icons.add,
          onPressed: () {
            final d = controller.activeDoc!;
            controller.addTopic(docId, d.rootId);
          },
        ),
        _ToolButton(
          text: 'Subtópico',
          icon: Icons.subdirectory_arrow_right,
          onPressed: () {
            final d = controller.activeDoc!;
            final selected = editor?.selectedNodeId ?? d.rootId;
            controller.addSubtopic(docId, selected);
          },
        ),
        _ToolButton(
          text: 'Flutuante',
          icon: Icons.bubble_chart_outlined,
          onPressed: () => editor?.addFloatingAtCenter(),
        ),
        const _ToolDivider(),
        _ToolButton(
          text: 'Anexar',
          icon: Icons.attach_file,
          onPressed: () => editor?.attachFiles(),
        ),
        _ToolButton(
          text: 'Link',
          icon: Icons.link,
          onPressed: () => editor?.editLink(),
        ),
      ];
    } else if (ribbonIndex == 2) {
      buttons = [
        _ToolButton(
          text: 'Cor do ramo',
          icon: Icons.color_lens_outlined,
          onPressed: () => editor?.cycleBranchColor(),
        ),
        _ToolButton(
          text: 'Preenchimento',
          icon: Icons.format_color_fill,
          onPressed: () => editor?.cycleFillColor(),
        ),
        _ToolButton(
          text: 'Forma',
          icon: Icons.category_outlined,
          onPressed: () => editor?.cycleShape(),
        ),
        _ToolButton(
          text: 'Borda +',
          icon: Icons.border_outer,
          onPressed: () => editor?.increaseBorderWidth(),
        ),
      ];
    } else if (ribbonIndex == 3) {
      buttons = [
        _ToolButton(
          text: 'Centralizar',
          icon: Icons.center_focus_strong,
          onPressed: () => editor?.centerView(),
        ),
        _ToolButton(
          text: 'Salvar',
          icon: Icons.save_outlined,
          onPressed: () => controller.saveNow(docId),
        ),
        _ToolButton(
          text: 'Desfazer',
          icon: Icons.undo,
          onPressed: () => controller.undo(docId),
        ),
        _ToolButton(
          text: 'Refazer',
          icon: Icons.redo,
          onPressed: () => controller.redo(docId),
        ),
      ];
    } else {
      buttons = [
        _ToolButton(
          text: 'Tópico',
          icon: Icons.add,
          onPressed: () {
            final d = controller.activeDoc!;
            controller.addTopic(docId, d.rootId);
          },
        ),
        _ToolButton(
          text: 'Subtópico',
          icon: Icons.subdirectory_arrow_right,
          onPressed: () {
            final d = controller.activeDoc!;
            final selected = editor?.selectedNodeId ?? d.rootId;
            controller.addSubtopic(docId, selected);
          },
        ),
        _ToolButton(
          text: 'Flutuante',
          icon: Icons.bubble_chart_outlined,
          onPressed: () => editor?.addFloatingAtCenter(),
        ),
        const _ToolDivider(),
        _ToolButton(
          text: 'Copiar',
          icon: Icons.copy,
          onPressed: () => editor?.copySelected(),
        ),
        _ToolButton(
          text: 'Cortar',
          icon: Icons.cut,
          onPressed: () => editor?.cutSelected(),
        ),
        _ToolButton(
          text: 'Colar',
          icon: Icons.paste,
          onPressed: () => editor?.paste(),
        ),
        _ToolButton(
          text: 'Excluir',
          icon: Icons.delete_outline,
          onPressed: () => editor?.deleteSelected(),
        ),
        const _ToolDivider(),
        _ToolButton(
          text: 'Desfazer',
          icon: Icons.undo,
          onPressed: () => controller.undo(docId),
        ),
        _ToolButton(
          text: 'Refazer',
          icon: Icons.redo,
          onPressed: () => controller.redo(docId),
        ),
        const _ToolDivider(),
        _ToolButton(
          text: 'Centralizar',
          icon: Icons.center_focus_strong,
          onPressed: () => editor?.centerView(),
        ),
        _ToolButton(
          text: 'Salvar',
          icon: Icons.save_outlined,
          onPressed: () => controller.saveNow(docId),
        ),
        const _ToolDivider(),
        _ToolButton(
          text: 'Anexar arquivo',
          icon: Icons.attach_file,
          onPressed: () => editor?.attachFiles(),
        ),
        _ToolButton(
          text: 'Link',
          icon: Icons.link,
          onPressed: () => editor?.editLink(),
        ),
        const _ToolDivider(),
        _ToolButton(
          text: 'Abrir site',
          icon: Icons.public,
          onPressed: () {
            // TODO: troque pela URL do seu site:
                openExternalUrl('https://seu-site-aqui.com');
          },
        ),
      ];
    }

    // Toolbar “de ponta a ponta”, com scroll horizontal para nunca dar overflow.
    return SizedBox(
      height: 44,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(children: buttons),
      ),
    );
  }
}

class _ToolDivider extends StatelessWidget {
  const _ToolDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Container(
        width: 1,
        height: 26,
        color: Theme.of(context).dividerColor,
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton(
      {required this.text, required this.icon, required this.onPressed});
  final String text;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(text),
      ),
    );
  }
}

/// ============================
///  EDITOR PAGE (CANVAS + PROPERTIES)
/// ============================

class MindMapEditorPage extends StatefulWidget {
  const MindMapEditorPage({
    super.key,
    required this.controller,
    required this.docId,
  });

  final MindMapController controller;
  final String docId;

  @override
  State<MindMapEditorPage> createState() => MindMapEditorPageState();

  static MindMapEditorPageState? of(BuildContext context) {
    return context.findAncestorStateOfType<MindMapEditorPageState>();
  }
}

class MindMapEditorPageState extends State<MindMapEditorPage> {
  String? selectedNodeId;

  final TransformationController _transform = TransformationController();
  final FocusNode _focusNode = FocusNode();

  bool _isDragging = false;

  MindMapDoc get doc => widget.controller.activeDoc!;

  @override
  void initState() {
    super.initState();
    selectedNodeId = doc.rootId;
    WidgetsBinding.instance.addPostFrameCallback((_) => centerView());
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _transform.dispose();
    super.dispose();
  }

  void centerView() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = box.size;

    final root = doc.nodes[doc.rootId]!;
    final target = root.pos;

    // centraliza o target na tela
    final matrix = Matrix4.identity();
    matrix.translate(size.width / 2 - target.dx, size.height / 2 - target.dy);
    _transform.value = matrix;
    setState(() {});
  }

  Offset _sceneDelta(Offset screenDelta) {
    final scale = _transform.value.getMaxScaleOnAxis();
    if (scale == 0) return screenDelta;
    return screenDelta / scale;
  }

  /// ======= Toolbar/Context actions =======
  void deleteSelected() {
    final id = selectedNodeId;
    if (id == null) return;
    widget.controller.deleteNode(widget.docId, id);
    selectedNodeId = doc.rootId;
    setState(() {});
  }

  void copySelected() {
    final id = selectedNodeId;
    if (id == null) return;
    widget.controller.copyNode(widget.docId, id);
    _snack('Copiado');
  }

  void cutSelected() {
    final id = selectedNodeId;
    if (id == null) return;
    widget.controller.cutNode(widget.docId, id);
    selectedNodeId = doc.rootId;
    setState(() {});
    _snack('Cortado');
  }

  void paste() {
    final newId = widget.controller.pasteToRoot(widget.docId);
    if (newId != null) {
      selectedNodeId = newId;
      setState(() {});
      _snack('Colado (ligado na Ideia Principal)');
    } else {
      _snack('Nada para colar');
    }
  }

  void addFloatingAtCenter() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = box.size;
    final centerScreen = Offset(size.width / 2, size.height / 2);

    // converte screen->scene
    final inv = Matrix4.inverted(_transform.value);
    final v =
        inv.transform3(vmath.Vector3(centerScreen.dx, centerScreen.dy, 0));
    final near = Offset(v.x, v.y);

    final id = widget.controller.addFloating(widget.docId, near);
    selectedNodeId = id;
    setState(() {});
  }

  Future<void> attachFiles() async {
    final id = selectedNodeId;
    if (id == null) return;

    final downloads = kIsWeb ? null : getDownloadsPath();
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        dialogTitle: 'Escolha arquivos para anexar',
        initialDirectory: downloads,
      );
      if (result == null) return;

      final atts = <NodeAttachment>[];
      for (final f in result.files) {
        final path = f.path;
        if (path == null) continue;
        atts.add(NodeAttachment(name: f.name, path: path));
      }

      if (atts.isNotEmpty) {
        widget.controller.addAttachments(widget.docId, id, atts);
        _snack('Arquivo(s) anexado(s)');
      }
    } catch (e) {
      _snack('Erro ao anexar: $e');
    }
  }

  Future<void> editLink() async {
    final id = selectedNodeId;
    if (id == null) return;
    final n = doc.nodes[id]!;
    final url = await _promptText(
      context,
      title: 'Adicionar/editar link',
      initial: n.link ?? '',
      hint: 'https://...',
    );
    if (url == null) return;
    widget.controller.updateNodeLink(widget.docId, id, url.trim());
  }

  void cycleBranchColor() {
    final id = selectedNodeId;
    if (id == null) return;
    const colors = [
      '#FF5252',
      '#FFB300',
      '#00C853',
      '#2979FF',
      '#7C4DFF',
      '#00B8D4',
      '#FFFFFF'
    ];
    final n = doc.nodes[id]!;
    final currentIndex = colors.indexOf(n.branchColor);
    final next = colors[(currentIndex + 1) % colors.length];
    widget.controller.updateNodeStyle(widget.docId, id, branchColor: next);
  }

  void cycleFillColor() {
    final id = selectedNodeId;
    if (id == null) return;
    const colors = [
      '#1F2333',
      '#FF5252',
      '#FFB300',
      '#00C853',
      '#2979FF',
      '#7C4DFF',
      '#00B8D4',
      '#FFFFFF'
    ];
    final n = doc.nodes[id]!;
    final currentIndex = colors.indexOf(n.fillColor);
    final next = colors[(currentIndex + 1) % colors.length];
    widget.controller.updateNodeStyle(widget.docId, id, fillColor: next);
  }

  void cycleShape() {
    final id = selectedNodeId;
    if (id == null) return;
    const shapes = ['pill', 'rounded', 'rect', 'circle', 'label'];
    final n = doc.nodes[id]!;
    final currentIndex = shapes.indexOf(n.shape);
    final next = shapes[(currentIndex + 1) % shapes.length];
    widget.controller.updateNodeStyle(widget.docId, id, shape: next);
  }

  void increaseBorderWidth() {
    final id = selectedNodeId;
    if (id == null) return;
    final n = doc.nodes[id]!;
    final next = (n.borderWidth + 0.5).clamp(0.5, 6);
    widget.controller.updateNodeStyle(widget.docId, id, borderWidth: next);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// ======= Edit node text (Enter salva, Shift+Enter quebra linha) =======
  Future<void> _editNodeText(String nodeId) async {
    final n = doc.nodes[nodeId]!;
    final text = await _promptMultiline(
      context,
      title: 'Editar texto',
      initial: n.text,
      hint: 'Digite...',
    );
    if (text == null) return;
    widget.controller.updateNodeText(widget.docId, nodeId, text);
  }

  /// ======= Right click menu =======
  Future<void> _showContextMenu(Offset globalPos) async {
    final selected = selectedNodeId ?? doc.rootId;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          globalPos.dx, globalPos.dy, globalPos.dx, globalPos.dy),
      items: const [
        PopupMenuItem(value: 'topic', child: Text('Tópico')),
        PopupMenuItem(value: 'sub', child: Text('Subtópico')),
        PopupMenuItem(value: 'float', child: Text('Tópico flutuante')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'copy', child: Text('Copiar')),
        PopupMenuItem(value: 'cut', child: Text('Cortar')),
        PopupMenuItem(value: 'paste', child: Text('Colar')),
        PopupMenuItem(value: 'del', child: Text('Excluir')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'shape', child: Text('Alterar forma')),
        PopupMenuItem(value: 'color', child: Text('Trocar cor')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'link', child: Text('Link')),
        PopupMenuItem(value: 'attach', child: Text('Anexar arquivo')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'center', child: Text('Centralizar')),
        PopupMenuItem(value: 'save', child: Text('Salvar')),
      ],
    );

    if (choice == null) return;
    switch (choice) {
      case 'topic':
        widget.controller.addTopic(widget.docId, doc.rootId);
        break;
      case 'sub':
        widget.controller.addSubtopic(widget.docId, selected);
        break;
      case 'float':
        addFloatingAtCenter();
        break;
      case 'copy':
        copySelected();
        break;
      case 'cut':
        cutSelected();
        break;
      case 'paste':
        paste();
        break;
      case 'del':
        deleteSelected();
        break;
      case 'shape':
        cycleShape();
        break;
      case 'color':
        cycleFillColor();
        break;
      case 'link':
        editLink();
        break;
      case 'attach':
        attachFiles();
        break;
      case 'center':
        centerView();
        break;
      case 'save':
        widget.controller.saveNow(widget.docId);
        _snack('Salvo');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = doc;
    final selected = selectedNodeId != null ? d.nodes[selectedNodeId!] : null;
    final bg = Theme.of(context).colorScheme.surface;

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.delete):
            const _DeleteIntent(),
        const SingleActivator(LogicalKeyboardKey.enter): const _AddSubIntent(),
        const SingleActivator(LogicalKeyboardKey.f2): const _EditIntent(),
        const SingleActivator(LogicalKeyboardKey.keyC, control: true):
            const _CopyIntent(),
        const SingleActivator(LogicalKeyboardKey.keyX, control: true):
            const _CutIntent(),
        const SingleActivator(LogicalKeyboardKey.keyV, control: true):
            const _PasteIntent(),
        const SingleActivator(LogicalKeyboardKey.digit0, control: true):
            const _CenterIntent(),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            const _SaveIntent(),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            const _UndoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true):
            const _RedoIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _DeleteIntent: CallbackAction<_DeleteIntent>(
              onInvoke: (_) => deleteSelected()),
          _AddSubIntent: CallbackAction<_AddSubIntent>(onInvoke: (_) {
            final sel = selectedNodeId ?? d.rootId;
            widget.controller.addSubtopic(widget.docId, sel);
            return null;
          }),
          _EditIntent: CallbackAction<_EditIntent>(onInvoke: (_) {
            final sel = selectedNodeId;
            if (sel != null) _editNodeText(sel);
            return null;
          }),
          _CopyIntent:
              CallbackAction<_CopyIntent>(onInvoke: (_) => copySelected()),
          _CutIntent:
              CallbackAction<_CutIntent>(onInvoke: (_) => cutSelected()),
          _PasteIntent:
              CallbackAction<_PasteIntent>(onInvoke: (_) => paste()),
          _CenterIntent:
              CallbackAction<_CenterIntent>(onInvoke: (_) => centerView()),
          _SaveIntent: CallbackAction<_SaveIntent>(
              onInvoke: (_) => widget.controller.saveNow(widget.docId)),
          _UndoIntent:
              CallbackAction<_UndoIntent>(onInvoke: (_) => widget.controller.undo(widget.docId)),
          _RedoIntent:
              CallbackAction<_RedoIntent>(onInvoke: (_) => widget.controller.redo(widget.docId)),
        },
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          child: Row(
            children: [
              // Canvas
              Expanded(
                child: Container(
                  color: bg,
                  child: Listener(
                    onPointerDown: (_) => _focusNode.requestFocus(),
                    child: GestureDetector(
                      onSecondaryTapDown: (d) => _showContextMenu(d.globalPosition),
                      child: InteractiveViewer(
                        transformationController: _transform,
                        panEnabled: true,
                        scaleEnabled: true,
                        minScale: 0.2,
                        maxScale: 2.8,
                        child: Stack(
                          children: [
                            CustomPaint(
                              painter: _EdgesPainter(doc: d),
                              size: const Size(5000, 3000),
                            ),
                            ...d.nodes.values.map((n) {
                              final isSelected = n.id == selectedNodeId;
                              return Positioned(
                                left: n.pos.dx + 2000, // offset “canvas grande”
                                top: n.pos.dy + 1200,
                                child: _NodeWidget(
                                  node: n,
                                  isSelected: isSelected,
                                  onTap: () async {
                                    if (selectedNodeId == n.id) {
                                      await _editNodeText(n.id);
                                    } else {
                                      setState(() => selectedNodeId = n.id);
                                    }
                                  },
                                  onDragStart: () =>
                                      setState(() => _isDragging = true),
                                  onDragUpdate: (delta) {
                                    final scene = _sceneDelta(delta);
                                    widget.controller
                                        .moveNode(widget.docId, n.id, n.pos + scene);
                                  },
                                  onDragEnd: () {
                                    setState(() => _isDragging = false);
                                    widget.controller.commitMove(widget.docId);
                                  },
                                  onContextMenu: (pos) {
                                    setState(() => selectedNodeId = n.id);
                                    _showContextMenu(pos);
                                  },
                                ),
                              );
                            }),
                            if (_isDragging)
                              Positioned(
                                right: 18,
                                bottom: 14,
                                child: Text(
                                  'Arrastando...',
                                  style: Theme.of(context).textTheme.labelMedium,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Properties panel
              Container(
                width: 340,
                decoration: BoxDecoration(
                  border: Border(
                      left: BorderSide(color: Theme.of(context).dividerColor)),
                ),
                child: _PropertiesPanel(
                  controller: widget.controller,
                  docId: widget.docId,
                  node: selected,
                  onEdit: () {
                    final id = selectedNodeId;
                    if (id != null) _editNodeText(id);
                  },
                  onOpenLink: () {
                    final link = selected?.link;
                    if (link != null && link.trim().isNotEmpty) {
                      openExternalUrl(link.trim());
                    }
                  },
                  onOpenFile: (path) => openFile(path),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keyboard intents
class _DeleteIntent extends Intent {
  const _DeleteIntent();
}

class _AddSubIntent extends Intent {
  const _AddSubIntent();
}

class _EditIntent extends Intent {
  const _EditIntent();
}

class _CopyIntent extends Intent {
  const _CopyIntent();
}

class _CutIntent extends Intent {
  const _CutIntent();
}

class _PasteIntent extends Intent {
  const _PasteIntent();
}

class _CenterIntent extends Intent {
  const _CenterIntent();
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

/// ============================
///  NODE WIDGET + EDGES
/// ============================

class _NodeWidget extends StatelessWidget {
  const _NodeWidget({
    required this.node,
    required this.isSelected,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onContextMenu,
  });

  final MindMapNode node;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final ValueChanged<Offset> onContextMenu;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final borderColor = _parseHex(node.borderColor ?? node.branchColor) ?? cs.primary;
    final fillColor = _parseHex(node.fillColor ?? '') ??
        (node.shape == 'label'
            ? Colors.transparent
            : Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.35));
    final textColor = _parseHex(node.textColor ?? '') ??
        (node.shape == 'label' ? borderColor : cs.onSurface);

    final style = GoogleFonts.getFont(
      node.fontFamily,
      fontSize: node.fontSize,
      fontWeight:
          node.id.startsWith('root_') ? FontWeight.w700 : FontWeight.w600,
      color: textColor,
    );

    if (node.shape == 'label') {
      return GestureDetector(
        onTap: onTap,
        onSecondaryTapDown: (d) => onContextMenu(d.globalPosition),
        onPanStart: (_) => onDragStart(),
        onPanUpdate: (d) => onDragUpdate(d.delta),
        onPanEnd: (_) => onDragEnd(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: borderColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(node.text, style: style),
            ],
          ),
        ),
      );
    }

    final shapeBorder = node.shape == 'circle'
        ? const CircleBorder()
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
                node.shape == 'rect' ? 6 : node.shape == 'rounded' ? 14 : 20),
          );

    return GestureDetector(
      onTap: onTap,
      onSecondaryTapDown: (d) => onContextMenu(d.globalPosition),
      onPanStart: (_) => onDragStart(),
      onPanUpdate: (d) => onDragUpdate(d.delta),
      onPanEnd: (_) => onDragEnd(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        constraints: const BoxConstraints(minWidth: 160, maxWidth: 320),
        decoration: ShapeDecoration(
          color: fillColor,
          shape: shapeBorder.copyWith(
            side: BorderSide(
              color: isSelected ? cs.primary : borderColor.withOpacity(0.8),
              width: isSelected ? 2 : node.borderWidth,
            ),
          ),
          shadows: [
            BoxShadow(
              blurRadius: 14,
              spreadRadius: 0,
              color: Colors.black.withOpacity(
                  Theme.of(context).brightness == Brightness.dark ? 0.35 : 0.08),
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 5,
              height: 34,
              decoration: BoxDecoration(
                color: borderColor,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(node.text, style: style),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (node.attachments.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.attach_file, size: 16),
                        ),
                      if (node.link != null && node.link!.trim().isNotEmpty)
                        const Icon(Icons.link, size: 16),
                      if (node.isFloating)
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(Icons.bubble_chart_outlined, size: 16),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EdgesPainter extends CustomPainter {
  _EdgesPainter({required this.doc});

  final MindMapDoc doc;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = doc.connectorWidth
      ..strokeCap = StrokeCap.round;

    for (final node in doc.nodes.values) {
      final parentId = node.parentId;
      if (parentId == null) continue;
      final parent = doc.nodes[parentId];
      if (parent == null) continue;

      final p1 = parent.pos + const Offset(2000, 1200);
      final p2 = node.pos + const Offset(2000, 1200);

      paint.color =
          (_parseHex(node.branchColor) ?? Colors.white).withOpacity(0.95);

      final path = Path();
      final start = p1 + const Offset(220, 26);
      final end = p2 + const Offset(0, 26);

      switch (doc.connectorStyle) {
        case 'straight':
          path.moveTo(start.dx, start.dy);
          path.lineTo(end.dx, end.dy);
          break;
        case 'elbow':
          final midX = (start.dx + end.dx) / 2;
          path.moveTo(start.dx, start.dy);
          path.lineTo(midX, start.dy);
          path.lineTo(midX, end.dy);
          path.lineTo(end.dx, end.dy);
          break;
        default:
          final dx = (end.dx - start.dx).abs();
          final control1 = start + Offset(dx * 0.45, 0);
          final control2 = end - Offset(dx * 0.45, 0);
          path.moveTo(start.dx, start.dy);
          path.cubicTo(control1.dx, control1.dy, control2.dx, control2.dy,
              end.dx, end.dy);
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EdgesPainter oldDelegate) => true;
}

/// ============================
///  PROPERTIES PANEL
/// ============================

class _PropertiesPanel extends StatelessWidget {
  const _PropertiesPanel({
    required this.controller,
    required this.docId,
    required this.node,
    required this.onEdit,
    required this.onOpenLink,
    required this.onOpenFile,
  });

  final MindMapController controller;
  final String docId;
  final MindMapNode? node;
  final VoidCallback onEdit;
  final VoidCallback onOpenLink;
  final ValueChanged<String> onOpenFile;

  @override
  Widget build(BuildContext context) {
    final n = node;
    if (n == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Selecione um bloco para ver as propriedades.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    final fonts = const [
      'Inter',
      'Poppins',
      'Montserrat',
      'Nunito',
      'Roboto',
      'Lato',
      'Oswald',
    ];
    final shapes = const {
      'pill': 'Pílula',
      'rounded': 'Arredondado',
      'rect': 'Retângulo',
      'circle': 'Círculo',
      'label': 'Etiqueta',
    };
    final borderStyles = const {
      'solid': 'Sólido',
      'dashed': 'Tracejado',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: ListView(
        children: [
          Text('PinealMap', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Text('Propriedades', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Text('Texto', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Text(n.text),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit),
            label: const Text('Editar (F2)'),
          ),
          const SizedBox(height: 18),
          Text('Cor do ramo', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in const [
                '#FF5252',
                '#FFB300',
                '#00C853',
                '#2979FF',
                '#7C4DFF',
                '#00B8D4',
                '#FFFFFF'
              ])
                _ColorDot(
                  hex: c,
                  selected: n.branchColor == c,
                  onTap: () =>
                      controller.updateNodeStyle(docId, n.id, branchColor: c),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text('Preenchimento', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in const [
                '#1F2333',
                '#FF5252',
                '#FFB300',
                '#00C853',
                '#2979FF',
                '#7C4DFF',
                '#00B8D4',
                '#FFFFFF'
              ])
                _ColorDot(
                  hex: c,
                  selected: n.fillColor == c,
                  onTap: () =>
                      controller.updateNodeStyle(docId, n.id, fillColor: c),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text('Borda', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in const [
                '#FFFFFF',
                '#1F2333',
                '#FF5252',
                '#FFB300',
                '#00C853',
                '#2979FF',
                '#7C4DFF',
                '#00B8D4'
              ])
                _ColorDot(
                  hex: c,
                  selected: n.borderColor == c,
                  onTap: () =>
                      controller.updateNodeStyle(docId, n.id, borderColor: c),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Espessura da borda',
              style: Theme.of(context).textTheme.labelLarge),
          Slider(
            min: 0.5,
            max: 6,
            value: n.borderWidth.clamp(0.5, 6),
            onChanged: (v) =>
                controller.updateNodeStyle(docId, n.id, borderWidth: v),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: borderStyles.containsKey(n.borderStyle)
                ? n.borderStyle
                : borderStyles.keys.first,
            items: borderStyles.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              controller.updateNodeStyle(docId, n.id, borderStyle: v);
            },
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Estilo da borda',
            ),
          ),
          const SizedBox(height: 18),
          Text('Forma', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: shapes.containsKey(n.shape) ? n.shape : shapes.keys.first,
            items: shapes.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              controller.updateNodeStyle(docId, n.id, shape: v);
            },
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 18),
          Text('Fonte', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: fonts.contains(n.fontFamily) ? n.fontFamily : fonts.first,
            items:
                fonts.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
            onChanged: (v) {
              if (v == null) return;
              controller.updateNodeStyle(docId, n.id, fontFamily: v);
            },
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          Text('Tamanho', style: Theme.of(context).textTheme.labelLarge),
          Slider(
            min: 12,
            max: 34,
            value: n.fontSize.clamp(12, 34),
            onChanged: (v) => controller.updateNodeStyle(docId, n.id, fontSize: v),
          ),
          const SizedBox(height: 18),
          Text('Ramo', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: const ['curved', 'straight', 'elbow']
                    .contains(controller.activeDoc?.connectorStyle)
                ? controller.activeDoc?.connectorStyle
                : 'curved',
            items: const [
              DropdownMenuItem(value: 'curved', child: Text('Curvo')),
              DropdownMenuItem(value: 'straight', child: Text('Reto')),
              DropdownMenuItem(value: 'elbow', child: Text('Cotovelado')),
            ],
            onChanged: (v) {
              if (v == null) return;
              controller.updateConnectorStyle(docId, connectorStyle: v);
            },
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Estilo do conector',
            ),
          ),
          const SizedBox(height: 10),
          Text('Espessura do conector',
              style: Theme.of(context).textTheme.labelLarge),
          Slider(
            min: 1,
            max: 8,
            value: (controller.activeDoc?.connectorWidth ?? 3).clamp(1, 8),
            onChanged: (v) =>
                controller.updateConnectorStyle(docId, connectorWidth: v),
          ),
          const SizedBox(height: 18),
          Text('Link', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  (n.link == null || n.link!.trim().isEmpty) ? '—' : n.link!,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Abrir link',
                onPressed:
                    (n.link == null || n.link!.trim().isEmpty) ? null : onOpenLink,
                icon: const Icon(Icons.open_in_new),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Arquivos anexados',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          if (n.attachments.isEmpty)
            const Text('Nenhum arquivo anexado.')
          else
            ...List.generate(n.attachments.length, (i) {
              final a = n.attachments[i];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(a.name, overflow: TextOverflow.ellipsis),
                subtitle: Text(a.path, overflow: TextOverflow.ellipsis),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Abrir',
                      onPressed: () => onOpenFile(a.path),
                      icon: const Icon(Icons.open_in_new),
                    ),
                    IconButton(
                      tooltip: 'Remover',
                      onPressed: () =>
                          controller.removeAttachment(docId, n.id, i),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 16),
          Text('Atalhos', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          const _ShortcutRow('Enter', 'Subtópico'),
          const _ShortcutRow('F2', 'Editar'),
          const _ShortcutRow('Del', 'Excluir'),
          const _ShortcutRow('Ctrl+C', 'Copiar'),
          const _ShortcutRow('Ctrl+X', 'Cortar'),
          const _ShortcutRow('Ctrl+V', 'Colar'),
          const _ShortcutRow('Ctrl+Z', 'Desfazer'),
          const _ShortcutRow('Ctrl+Y', 'Refazer'),
          const _ShortcutRow('Ctrl+0', 'Centralizar'),
          const _ShortcutRow('Ctrl+S', 'Salvar'),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow(this.k, this.desc);
  final String k;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Text(k),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(desc)),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.hex, required this.selected, required this.onTap});

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = _parseHex(hex) ?? Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}

/// ============================
///  EDIT DIALOGS (Enter salva / Shift+Enter quebra linha)
/// ============================

Future<String?> _promptText(
  BuildContext context, {
  required String title,
  required String initial,
  required String hint,
}) async {
  final controller = TextEditingController(text: initial);
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(hintText: hint),
        autofocus: true,
        onSubmitted: (_) => Navigator.of(context).pop(true),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('OK')),
      ],
    ),
  );

  if (ok != true) return null;
  return controller.text.trim();
}

Future<String?> _promptMultiline(
  BuildContext context, {
  required String title,
  required String initial,
  required String hint,
}) async {
  final tc = TextEditingController(text: initial);

  // Enter salva / Shift+Enter quebra linha
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 560,
        height: 240,
        child: _EnterToSaveTextField(controller: tc, hint: hint),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Salvar')),
      ],
    ),
  );

  if (ok != true) return null;
  return tc.text.trim().isEmpty ? initial : tc.text.trim();
}

class _EnterToSaveTextField extends StatelessWidget {
  const _EnterToSaveTextField({required this.controller, required this.hint});
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): _SaveTextIntent(),
        SingleActivator(LogicalKeyboardKey.enter, shift: true):
            _InsertNewLineIntent(),
      },
      child: Actions(
        actions: {
          _SaveTextIntent: CallbackAction<_SaveTextIntent>(onInvoke: (_) {
            Navigator.of(context).pop(true);
            return null;
          }),
          _InsertNewLineIntent:
              CallbackAction<_InsertNewLineIntent>(onInvoke: (_) {
            final value = controller.value;
            final sel = value.selection;
            final text = value.text;
            final newText = text.replaceRange(sel.start, sel.end, '\n');
            final caret = sel.start + 1;
            controller.value = value.copyWith(
              text: newText,
              selection: TextSelection.collapsed(offset: caret),
            );
            return null;
          }),
        },
        child: TextField(
          controller: controller,
          autofocus: true,
          expands: true,
          maxLines: null,
          minLines: null,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
    );
  }
}

class _SaveTextIntent extends Intent {
  const _SaveTextIntent();
}

class _InsertNewLineIntent extends Intent {
  const _InsertNewLineIntent();
}

/// ============================
///  UTIL: open file / open url
/// ============================

// util functions live in platform_utils.dart

/// ============================
///  LOGO (PINECONE)
/// ============================

class PineconeLogo extends StatelessWidget {
  const PineconeLogo({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _PineconePainter(color: Theme.of(context).colorScheme.primary),
    );
  }
}

class _PineconePainter extends CustomPainter {
  _PineconePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color.withOpacity(0.95);
    final w = size.width;
    final h = size.height;

    // simples “pinha” estilizada
    final center = Offset(w / 2, h / 2);
    final r = min(w, h) / 2;

    // corpo
    final body = Path()
      ..moveTo(center.dx, center.dy - r * 0.9)
      ..cubicTo(
          center.dx + r * 0.8,
          center.dy - r * 0.4,
          center.dx + r * 0.7,
          center.dy + r * 0.7,
          center.dx,
          center.dy + r * 0.95)
      ..cubicTo(
          center.dx - r * 0.7,
          center.dy + r * 0.7,
          center.dx - r * 0.8,
          center.dy - r * 0.4,
          center.dx,
          center.dy - r * 0.9)
      ..close();
    canvas.drawPath(body, p);

    // “escamas”
    final s = Paint()..color = Colors.white.withOpacity(0.18);
    for (int i = 0; i < 5; i++) {
      final yy = center.dy - r * 0.45 + i * r * 0.28;
      final xx = center.dx;
      final oval = Rect.fromCenter(
          center: Offset(xx, yy),
          width: r * 1.05 - i * r * 0.12,
          height: r * 0.26);
      canvas.drawOval(oval, s);
    }

    // topo
    final top = Paint()..color = Colors.white.withOpacity(0.12);
    canvas.drawCircle(
        Offset(center.dx, center.dy - r * 0.75), r * 0.18, top);
  }

  @override
  bool shouldRepaint(covariant _PineconePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// ============================
///  HEX COLOR
/// ============================

Color? _parseHex(String hex) {
  try {
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    final v = int.parse(h, radix: 16);
    return Color(v);
  } catch (_) {
    return null;
  }
}
