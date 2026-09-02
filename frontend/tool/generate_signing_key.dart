import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

/// Crea una semilla Ed25519 para el emisor offline.
///
/// Usage:
///   dart run tool/generate_signing_key.dart
///   dart run tool/generate_signing_key.dart C:\ruta-segura\bdj-spp3.private.json
///
/// El archivo generado contiene una clave privada. Nunca lo agregues a Git,
/// nunca lo envíes a clientes y conserva una copia en un gestor seguro.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Uso: dart run tool/generate_signing_key.dart <archivo-salida>');
    exitCode = 64;
    return;
  }

  final output = File(arguments.single);
  if (await output.exists()) {
    stderr.writeln('El archivo de salida ya existe: ${output.path}');
    exitCode = 73;
    return;
  }

  final parent = output.parent;
  if (!await parent.exists()) {
    await parent.create(recursive: true);
  }

  final pair = await Ed25519().newKeyPair();
  final privateKey = base64UrlEncode(await pair.extractPrivateKeyBytes());
  final publicKey = base64UrlEncode((await pair.extractPublicKey()).bytes);
  await output.writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'format': 'bdj-ed25519-seed-v1',
      'privateKey': privateKey,
      'publicKey': publicKey,
    }),
    flush: true,
  );

  stdout.writeln('Clave pública para los builds: $publicKey');
  stdout.writeln('Clave privada guardada en: ${output.path}');
}
