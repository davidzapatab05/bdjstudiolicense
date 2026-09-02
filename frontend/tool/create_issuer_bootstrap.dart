import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

const _iterations = 210000;
const _alphabet =
    'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#%+-_';

/// Crea el archivo de primer inicio para una consola de superadministrador.
/// El resultado contiene una semilla de firma y un hash PBKDF2, nunca la clave
/// de acceso en texto plano. Guarde la clave impresa en un gestor de secretos.
Future<void> main(List<String> args) async {
  if (args.length < 3 || args.length > 4) {
    stderr.writeln(
      'Uso: dart run tool/create_issuer_bootstrap.dart '
      '<issuer.private.json> <issuer.bootstrap.json> <correo> [contrasena]',
    );
    exitCode = 64;
    return;
  }

  final input = File(args[0]);
  final output = File(args[1]);
  final email = args[2].trim().toLowerCase();
  if (!email.contains('@')) {
    stderr.writeln('El correo del superadministrador no es valido.');
    exitCode = 64;
    return;
  }
  final source = jsonDecode(await input.readAsString());
  if (source is! Map || source['privateKey'] is! String) {
    stderr.writeln('El archivo de firma no contiene privateKey.');
    exitCode = 65;
    return;
  }

  final random = Random.secure();
  final password = args.length == 4
      ? args[3]
      : List<String>.generate(
          24,
          (_) => _alphabet[random.nextInt(_alphabet.length)],
        ).join();
  if (password.length < 12) {
    stderr.writeln('La contrasena debe tener al menos 12 caracteres.');
    exitCode = 64;
    return;
  }
  final salt = List<int>.generate(16, (_) => random.nextInt(256));
  final algorithm = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  );
  final key = await algorithm.deriveKeyFromPassword(
    password: password,
    nonce: salt,
  );
  final hash = await key.extractBytes();
  final bootstrap = <String, Object>{
    'format': 'BDJ_ISSUER_BOOTSTRAP_V1',
    'privateKey': source['privateKey'] as String,
    'replaceAdmin': true,
    'admin': <String, String>{
      'email': email,
      'passwordHash': base64UrlEncode(hash),
      'passwordSalt': base64UrlEncode(salt),
    },
  };
  await output.parent.create(recursive: true);
  await output.writeAsString(
    const JsonEncoder.withIndent('  ').convert(bootstrap),
  );
  stdout.writeln('Correo: $email');
  stdout.writeln('Contrasena: $password');
  stdout.writeln('Bootstrap creado: ${output.path}');
}
