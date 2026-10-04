import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../file_actions.dart';
import '../io/file_io.dart';
import '../library.dart';
import '../services/app_log.dart';
import '../services/updates.dart';
import 'brand.dart';
import 'license_dialog.dart';

Future<void> _open(BuildContext context, String url) async {
  final ok = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  ).catchError((_) => false);
  if (!ok && context.mounted) showSnack(context, 'Não foi possível abrir $url');
}

Future<void> _openFolder(BuildContext context, String? path) async {
  if (path == null) return;
  final ok = await launchUrl(Uri.directory(path)).catchError((_) => false);
  if (!ok && context.mounted) {
    showSnack(context, 'Pasta ainda não existe: $path');
  }
}

// =====================================================================
// Configurações
// =====================================================================

Future<void> showSettingsDialog(BuildContext context, Library library) {
  return showDialog<void>(
    context: context,
    builder: (_) => _SettingsDialog(library: library),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.library});
  final Library library;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  bool _checking = false;
  String? _updateMessage;

  Library get lib => widget.library;

  Future<void> _checkNow() async {
    setState(() {
      _checking = true;
      _updateMessage = null;
    });
    final info = await checkForUpdate();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _updateMessage = info == null
          ? 'Você está com a versão mais recente ($kAppVersion).'
          : 'Nova versão disponível: ${info.version}.';
    });
    if (info != null) await showUpdateDialog(context, info);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final dataDir = appDataDir();
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.settings_outlined),
            SizedBox(width: 10),
            Text('Configurações'),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Licença', style: t.titleSmall),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    lib.isLicensed
                        ? Icons.verified_outlined
                        : lib.readOnly
                        ? Icons.lock_outline
                        : Icons.hourglass_top_outlined,
                    color: lib.readOnly
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(licenseStatusText(lib)),
                  trailing: FilledButton.tonal(
                    key: const Key('settings-license'),
                    onPressed: () => showLicenseDialog(context, lib),
                    child: Text(lib.isLicensed ? 'Detalhes' : 'Ativar licença'),
                  ),
                ),
                const Divider(height: 24),
                Text('Aparência', style: t.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_outlined),
                      label: Text('Sistema'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('Claro'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('Escuro'),
                    ),
                  ],
                  selected: {lib.themeMode},
                  onSelectionChanged: (s) => lib.setThemeMode(s.first),
                ),
                const Divider(height: 32),
                Text('Atualizações', style: t.titleSmall),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Avisar quando houver versão nova'),
                  subtitle: const Text('Consulta o GitHub ao abrir o MapLong'),
                  value: lib.checkUpdates,
                  onChanged: lib.setCheckUpdates,
                ),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _checking ? null : _checkNow,
                      icon: _checking
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.system_update_alt),
                      label: const Text('Verificar agora'),
                    ),
                    const SizedBox(width: 12),
                    if (_updateMessage != null)
                      Expanded(
                        child: Text(_updateMessage!, style: t.bodySmall),
                      ),
                  ],
                ),
                const Divider(height: 32),
                Text('Ajuda', style: t.titleSmall),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mostrar boas-vindas ao abrir'),
                  value: !lib.welcomeSeen,
                  onChanged: (v) {
                    if (v) {
                      lib.resetWelcome();
                    } else {
                      lib.markWelcomeSeen();
                    }
                    setState(() {});
                  },
                ),
                if (dataDir != null) ...[
                  const Divider(height: 32),
                  Text('Seus dados', style: t.titleSmall),
                  const SizedBox(height: 4),
                  SelectableText(dataDir, style: t.bodySmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _openFolder(context, dataDir),
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('Abrir pasta dos dados'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _openFolder(context, AppLog.folder),
                        icon: const Icon(Icons.bug_report_outlined),
                        label: const Text('Registro de erros'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Sobre
// =====================================================================

Future<void> showAboutMapLong(BuildContext context, {Library? library}) {
  final t = Theme.of(context).textTheme;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              const MapLongSymbol(height: 64),
              const SizedBox(height: 12),
              const MapLongWordmark(fontSize: 28),
              const SizedBox(height: 6),
              Text('Versão $kAppVersion', style: t.bodyMedium),
              if (library != null) ...[
                const SizedBox(height: 4),
                Text(licenseStatusText(library), style: t.bodySmall),
              ],
              const SizedBox(height: 12),
              Text(
                'Mapas mentais que funcionam offline e salvam tudo no seu '
                'computador.',
                textAlign: TextAlign.center,
                style: t.bodyMedium,
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _open(ctx, kTutorialUrl),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('Tutorial'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _open(ctx, kRepoUrl),
                    icon: const Icon(Icons.code),
                    label: const Text('Código no GitHub'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _open(ctx, kIssuesUrl),
                    icon: const Icon(Icons.feedback_outlined),
                    label: const Text('Relatar problema'),
                  ),
                ],
              ),
              const Divider(height: 32),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Serviços usados (gratuitos)', style: t.titleSmall),
              ),
              const SizedBox(height: 6),
              for (final (name, use) in const [
                ('Wikipédia', 'resumos e seções de artigos (CC BY-SA)'),
                ('Openverse', 'imagens livres (Creative Commons)'),
                ('BrasilAPI', 'feriados nacionais'),
                ('The Color API', 'paletas de cores'),
                ('GitHub', 'aviso de novas versões'),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  '),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              TextSpan(text: ' — $use'),
                            ],
                          ),
                          style: t.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => showLicensePage(
            context: ctx,
            applicationName: kAppName,
            applicationVersion: kAppVersion,
            applicationIcon: const Padding(
              padding: EdgeInsets.all(8),
              child: MapLongSymbol(height: 40),
            ),
          ),
          child: const Text('Licenças de código aberto'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}

// =====================================================================
// Atualização disponível
// =====================================================================

Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.system_update_alt),
          const SizedBox(width: 10),
          Text('MapLong ${info.version} disponível'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Você está usando a versão $kAppVersion.'),
              if (info.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Novidades', style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 4),
                SelectableText(info.notes),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Depois'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(ctx);
            _open(context, info.downloadUrl ?? info.url);
          },
          icon: const Icon(Icons.download),
          label: Text(
            info.downloadUrl == null ? 'Ver no GitHub' : 'Baixar instalador',
          ),
        ),
      ],
    ),
  );
}

// =====================================================================
// Boas-vindas
// =====================================================================

Future<void> showWelcomeDialog(BuildContext context, Library library) async {
  final t = Theme.of(context).textTheme;
  const tips = [
    (
      Icons.add_circle_outline,
      'Comece rápido',
      'Use um modelo, um mapa em branco ou cole um texto em '
          '"Texto para mapa mental".',
    ),
    (
      Icons.keyboard_outlined,
      'Atalhos que fazem diferença',
      'Tab cria um subtópico, Enter um tópico irmão. '
          'Dois cliques editam; três cliques criam um tópico ligado.',
    ),
    (
      Icons.perm_media_outlined,
      'Tudo num lugar só',
      'Arraste imagens e documentos para o mapa, adicione links, tarefas, '
          'fórmulas e pesquise na Wikipédia.',
    ),
    (
      Icons.cloud_done_outlined,
      'Salvo automaticamente',
      'Cada alteração é guardada na hora, com histórico de versões. '
          'Use Ctrl+S para salvar um arquivo .maplong.',
    ),
  ];
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MapLongSymbol(height: 56),
            const SizedBox(height: 10),
            Text('Bem-vindo ao MapLong', style: t.headlineSmall),
            const SizedBox(height: 20),
            for (final (icon, title, text) in tips)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: Theme.of(ctx).colorScheme.primary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: t.titleSmall),
                          Text(text, style: t.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _open(ctx, kTutorialUrl),
          child: const Text('Ver o tutorial'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Começar'),
        ),
      ],
    ),
  );
  library.markWelcomeSeen();
}
