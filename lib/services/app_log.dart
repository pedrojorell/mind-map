import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_info.dart';
import '../io/file_io.dart';

/// Registro de erros do MapLong. No computador grava em
/// `<pasta de dados>/logs/maplong.log`; no navegador, só no console.
class AppLog {
  AppLog._();

  /// Chave do ScaffoldMessenger do app, para avisar o usuário de erros.
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// Pasta dos registros (nula no navegador).
  static String? get folder {
    final dir = appDataDir();
    return dir == null ? null : '$dir${_sep(dir)}logs';
  }

  static String? get file {
    final f = folder;
    return f == null ? null : '$f${_sep(f)}maplong.log';
  }

  static String _sep(String path) => path.contains('\\') ? '\\' : '/';

  static DateTime _lastNotice = DateTime(0);

  /// Registra um erro e, se [notify], mostra um aviso discreto ao usuário
  /// (no máximo um a cada 10 segundos).
  static Future<void> error(
    Object error,
    StackTrace? stack, {
    String context = '',
    bool notify = true,
  }) async {
    final line = StringBuffer()
      ..write('[${DateTime.now().toIso8601String()}] ')
      ..write('MapLong $kAppVersion')
      ..write(context.isEmpty ? '' : ' ($context)')
      ..write(': $error');
    if (stack != null) line.write('\n$stack');
    debugPrint(line.toString());

    final path = file;
    if (path != null) {
      try {
        await appendLine(path, line.toString());
      } catch (_) {
        // Sem permissão para gravar o registro: ignora.
      }
    }

    final now = DateTime.now();
    if (notify && now.difference(_lastNotice) > const Duration(seconds: 10)) {
      _lastNotice = now;
      messengerKey.currentState?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          width: 460,
          content: const Text(
            'Algo deu errado, mas seus mapas estão salvos. '
            'O detalhe foi gravado no registro de erros.',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  /// Captura erros não tratados do Flutter e do Dart.
  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      unawaited(error(details.exception, details.stack, context: 'interface'));
    };
    PlatformDispatcher.instance.onError = (e, stack) {
      unawaited(error(e, stack, context: 'assíncrono'));
      return true; // Tratado: o app continua aberto.
    };
  }
}
