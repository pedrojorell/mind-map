/// Licenças do MapLong.
///
/// Uma licença é um código assinado pelo gerador do proprietário
/// (`licencas/gerador.mjs` ou o servidor de vendas):
///
///     MAPLONG-<dados>.<assinatura>
///
/// O app guarda só a chave PÚBLICA e confere a assinatura sem internet.
/// Sem a chave privada (que fica apenas com o dono) não dá para criar um
/// código que o app aceite.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Chave pública do gerador de licenças (Ed25519, base64url).
const kLicensePublicKey = 'EQhf50P_HU-UP_BDqRGXXti2pLp5JzKW8B0vH3ebmJM';

const kLicensePrefix = 'MAPLONG-';

/// Dias de teste grátis com tudo liberado.
const kTrialDays = 7;

const kLicensePrice = r'R$ 69,00';

/// Página de compra (servidor de vendas publicado no Cloudflare).
/// Vazio enquanto a loja não estiver no ar: o botão "Comprar" fica oculto.
const kStoreUrl = '';

enum LicensePlan {
  pro('pro', 'Pro vitalícia'),
  owner('dono', 'Proprietário');

  const LicensePlan(this.code, this.label);

  /// Como o plano aparece dentro do código.
  final String code;
  final String label;
}

class License {
  const License({
    required this.id,
    required this.plan,
    required this.email,
    required this.issued,
    required this.code,
  });

  /// Identificador da venda (ex.: "MP-123" para Mercado Pago).
  final String id;
  final LicensePlan plan;
  final String email;

  /// Data de emissão (AAAA-MM-DD).
  final String issued;

  /// O código completo, como foi ativado.
  final String code;

  bool get isOwner => plan == LicensePlan.owner;

  /// Data de emissão no formato DD/MM/AAAA.
  String get issuedLabel {
    final p = issued.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : issued;
  }
}

class LicenseException implements Exception {
  const LicenseException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Remove espaços, quebras de linha e aspas que vêm junto ao copiar.
String normalizeLicenseCode(String raw) =>
    raw.replaceAll(RegExp('[\\s"\'`<>]'), '');

Uint8List _fromBase64Url(String s) {
  if (!RegExp(r'^[A-Za-z0-9_-]*$').hasMatch(s)) {
    throw const LicenseException('O código tem caracteres inválidos.');
  }
  try {
    return base64Url.decode(base64Url.normalize(s));
  } on FormatException {
    throw const LicenseException('Código incompleto. Copie o código inteiro.');
  }
}

/// Confere o código e devolve a licença. Lança [LicenseException] com uma
/// mensagem para o usuário quando o código não vale.
Future<License> verifyLicense(
  String raw, {
  String publicKey = kLicensePublicKey,
}) async {
  final code = normalizeLicenseCode(raw);
  if (code.isEmpty) {
    throw const LicenseException('Cole o código da licença.');
  }
  if (!code.toUpperCase().startsWith(kLicensePrefix)) {
    throw const LicenseException('O código deve começar com MAPLONG-.');
  }
  final parts = code.substring(kLicensePrefix.length).split('.');
  if (parts.length != 2 || parts.any((p) => p.isEmpty)) {
    throw const LicenseException('Código incompleto. Copie o código inteiro.');
  }
  final payload = _fromBase64Url(parts[0]);
  final signature = _fromBase64Url(parts[1]);

  var valid = false;
  if (signature.length == 64) {
    try {
      valid = await Ed25519().verify(
        payload,
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(
            base64Url.decode(base64Url.normalize(publicKey)),
            type: KeyPairType.ed25519,
          ),
        ),
      );
    } catch (_) {
      valid = false;
    }
  }
  if (!valid) {
    throw const LicenseException(
      'Código inválido. Confira se você copiou o código inteiro.',
    );
  }

  final Map<String, dynamic> j;
  try {
    j = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
  } catch (_) {
    throw const LicenseException('Código inválido.');
  }
  if (j['v'] != 1) {
    throw const LicenseException(
      'Este código é de uma versão mais nova do MapLong. Atualize o app.',
    );
  }
  final plan = LicensePlan.values.where((p) => p.code == j['p']).firstOrNull;
  if (plan == null) {
    throw const LicenseException('Plano de licença desconhecido.');
  }
  return License(
    id: '${j['id'] ?? ''}',
    plan: plan,
    email: '${j['e'] ?? ''}',
    issued: '${j['d'] ?? ''}',
    code: kLicensePrefix + code.substring(kLicensePrefix.length),
  );
}
