import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bdj_license_core/bdj_license_core.dart';

class ProvisioningException implements Exception {
  final String message;
  ProvisioningException(this.message);
  @override
  String toString() => 'ProvisioningException: $message';
}

class SafeMacOsOptions extends MacOsOptions {
  const SafeMacOsOptions({
    super.accessibility = KeychainAccessibility.first_unlock,
    super.synchronizable = false,
    super.groupId,
    super.usesDataProtectionKeychain = false,
  });

  @override
  Map<String, String> toMap() {
    final map = <String, String>{
      ...super.toMap(),
      'usesDataProtectionKeychain': '$usesDataProtectionKeychain',
      'useDataProtectionKeyChain': '$usesDataProtectionKeychain',
    };
    if (!usesDataProtectionKeychain) {
      map.remove('accessibility');
      map.remove('synchronizable');
      map.remove('groupId');
    }
    return map;
  }
}

/// Gestor de provisión segura en tiempo de ejecución.
/// Evita compilar claves privadas vía --dart-define o incrustarlas en binarios.
class RuntimeProvisioner {
  final FlutterSecureStorage _storage;

  static const androidOptions = AndroidOptions();
  static const iOsOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );
  static const macOsOptions = SafeMacOsOptions(
    accessibility: KeychainAccessibility.first_unlock,
    synchronizable: false,
    groupId: null,
    usesDataProtectionKeychain: false,
  );
  static const windowsOptions = WindowsOptions();
  static const linuxOptions = LinuxOptions();

  RuntimeProvisioner({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: androidOptions,
            iOptions: iOsOptions,
            mOptions: macOsOptions,
            wOptions: windowsOptions,
            lOptions: linuxOptions,
          );

  /// Procesa un paquete de provisión (.bdjprov), descifra las claves en memoria
  /// utilizando la contraseña del operador, valida el certificado y el keyId,
  /// almacena de inmediato en Secure Storage y elimina el archivo temporal.
  Future<void> decryptAndProvision({
    required File packageFile,
    required String password,
    bool deleteFileAfterProvision = true,
  }) async {
    if (!await packageFile.exists()) {
      throw ProvisioningException('El archivo de provisión no existe.');
    }

    final jsonContent = await packageFile.readAsString();
    final Map<String, dynamic> package;
    try {
      package = jsonDecode(jsonContent) as Map<String, dynamic>;
    } catch (e) {
      throw ProvisioningException('Formato inválido del paquete de provisión.');
    }

    final keyId = package['keyId'] as String?;
    final ivBase64 = package['iv'] as String?;
    final saltBase64 = package['salt'] as String?;
    final cipherBase64 = package['ciphertext'] as String?;
    final macBase64 = package['mac'] as String?;
    final certEncoded = package['adminCertificate'] as String?;

    if (keyId == null ||
        ivBase64 == null ||
        saltBase64 == null ||
        cipherBase64 == null ||
        macBase64 == null ||
        certEncoded == null) {
      throw ProvisioningException(
        'Estructura de provisión corrupta o incompleta.',
      );
    }

    // 1. Validar certificado administrativo y keyId en memoria antes de descifrar
    final AdminCertificate cert;
    try {
      cert = AdminCertificate.fromEncodedString(certEncoded);
      if (cert.isExpired) {
        throw ProvisioningException('El certificado de operador ha expirado.');
      }
      if (cert.adminId != keyId) {
        throw ProvisioningException(
          'Discrepancia entre keyId y certificado del operador.',
        );
      }
    } catch (e) {
      throw ProvisioningException('Certificado administrativo inválido: $e');
    }

    // 2. Derivar clave de cifrado simétrico en memoria (PBKDF2 SHA-256)
    final salt = base64Decode(saltBase64);
    final iv = base64Decode(ivBase64);
    final cipherBytes = base64Decode(cipherBase64);
    final macBytes = base64Decode(macBase64);

    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 210000,
      bits: 256,
    );
    final secretKey = await pbkdf2.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );

    // 3. Descifrado AES-GCM únicamente en memoria
    final algorithm = AesGcm.with256bits();
    final secretBox = SecretBox(cipherBytes, nonce: iv, mac: Mac(macBytes));

    List<int> decryptedSeed;
    try {
      decryptedSeed = await algorithm.decrypt(secretBox, secretKey: secretKey);
    } catch (e) {
      throw ProvisioningException(
        'Contraseña incorrecta o paquete alterado y fallido al verificar MAC.',
      );
    }

    try {
      // 4. Comprobación del par de claves Ed25519 derivado en memoria
      final keyPair = await KeyHierarchy.generateKeyPairFromSeed(decryptedSeed);
      final pubKey = await keyPair.extractPublicKey();
      final derivedPubBase64 = base64UrlEncode(pubKey.bytes);
      final derivedPrivBase64 = base64UrlEncode(decryptedSeed);

      if (cert.operatorPublicKeyBase64 != derivedPubBase64) {
        throw ProvisioningException(
          'La clave descifrada no corresponde a la clave pública del certificado.',
        );
      }

      // 5. Almacenar directamente en Almacén Seguro Nativo (Secure Storage)
      await _storage.write(
        key: 'bdj_spp3_op_private',
        value: derivedPrivBase64,
      );
      await _storage.write(key: 'bdj_spp3_op_public', value: derivedPubBase64);
      await _storage.write(key: 'bdj_spp3_admin_cert', value: certEncoded);
    } finally {
      // 6. Limpieza en memoria: sobrescribir con ceros la semilla descifrada para prevenir lecturas por volcados de RAM
      for (int i = 0; i < decryptedSeed.length; i++) {
        decryptedSeed[i] = 0;
      }
    }

    // 7. Eliminación segura del archivo temporal del disco
    if (deleteFileAfterProvision) {
      try {
        if (await packageFile.exists()) {
          // Sobrescribir antes de borrar (shredding simple)
          final length = await packageFile.length();
          await packageFile.writeAsBytes(Uint8List(length), flush: true);
          await packageFile.delete();
        }
      } catch (_) {
        // En caso de que el SO tenga un bloqueo sobre el archivo temporal
      }
    }
    // IMPORTANTE: Ningún log omita ni registre jamás contenido de claves privadas.
  }

  /// Verifica que existan claves aprovisionadas y vigentes en el almacén seguro.
  Future<bool> isProvisionedAndValid() async {
    final priv = await _storage.read(key: 'bdj_spp3_op_private');
    final pub = await _storage.read(key: 'bdj_spp3_op_public');
    final certStr = await _storage.read(key: 'bdj_spp3_admin_cert');

    if (priv == null || pub == null || certStr == null) return false;
    try {
      final cert = AdminCertificate.fromEncodedString(certStr);
      return !cert.isExpired;
    } catch (_) {
      return false;
    }
  }
}
