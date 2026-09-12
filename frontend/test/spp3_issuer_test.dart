import 'package:bdj_license_core/bdj_license_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bdj_studio_license/main.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'LicenseIssuer emite tokens SPP3 verificables por la clave pública raíz',
    () async {
      SharedPreferences.setMockInitialValues({});

      // Mock de flutter_secure_storage en memoria para test
      final storageData = <String, String>{};
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'read') {
              final key = call.arguments['key'] as String;
              return storageData[key];
            }
            if (call.method == 'write') {
              final key = call.arguments['key'] as String;
              final value = call.arguments['value'] as String;
              storageData[key] = value;
              return null;
            }
            if (call.method == 'deleteAll') {
              storageData.clear();
              return null;
            }
            return null;
          });

      final issuer = LicenseIssuer();
      await issuer.load();

      expect(
        issuer.isConfigured,
        isTrue,
        reason:
            'El emisor debe quedar configurado con claves SPP3 de operador.',
      );

      final mockRecord = LicenseRecord(
        id: '12345678',
        product: 'bdj_studio_sample_pad',
        device: 'V1-TEST-DEVICE-0001',
        plan: 'pro',
        issuedAt: DateTime.now().toUtc(),
        customerId: 'customer-1',
        customerName: 'DJ Test',
        status: 'active',
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 365)),
        exactVersion: '1.0.3',
      );

      final token = await issuer.generateSpp3TokenForRecord(mockRecord);

      expect(
        token,
        startsWith('SPP3.'),
        reason: 'El token emitido debe utilizar el protocolo SPP3.',
      );
      expect(
        token.split('.').length,
        4,
        reason:
            'Debe contener prefijo, payload, certificado de administrador y firma de licencia.',
      );

      // Verificación criptográfica en el lado del cliente con bdj_license_core
      final hwidHash = KeyHierarchy.hashHwid('V1-TEST-DEVICE-0001');
      final verification = await Spp3Token.verify(
        token: token,
        rootPublicKeyBase64: KeyHierarchy.ecosystemRootPublicKey,
        expectedProductCode: 'bdj_studio_sample_pad',
        currentHwidHash: hwidHash,
        expectedVersion: '1.0.3',
      );

      expect(
        verification.status,
        equals(Spp3VerificationStatus.valid),
        reason:
            'La validación criptográfica en 2 etapas (Raíz -> Certificado Admin -> Firma Licencia) debe resultar exitosa.',
      );
      expect(verification.payload?.exactVersion, equals('1.0.3'));
    },
  );

  test(
    'LicenseIssuer emite y valida tokens SPP3 para bdj_studio_voice_spot',
    () async {
      final issuer = LicenseIssuer();
      await issuer.load();

      final voiceSpotRecord = LicenseRecord(
        id: 'vs-87654321',
        product: 'bdj_studio_voice_spot',
        device: 'V1-VOICE-SPOT-0001',
        plan: 'permanent',
        issuedAt: DateTime.now().toUtc(),
        customerId: 'customer-voice',
        customerName: 'Voice Artist Test',
        status: 'active',
        expiresAt: null,
        exactVersion: '1.0.0',
      );

      final token = await issuer.generateSpp3TokenForRecord(voiceSpotRecord);
      expect(token, startsWith('SPP3.'));

      final hwidHash = KeyHierarchy.hashHwid('V1-VOICE-SPOT-0001');
      final verification = await Spp3Token.verify(
        token: token,
        rootPublicKeyBase64: KeyHierarchy.ecosystemRootPublicKey,
        expectedProductCode: 'bdj_studio_voice_spot',
        currentHwidHash: hwidHash,
        expectedVersion: '1.0.0',
      );

      expect(verification.status, equals(Spp3VerificationStatus.valid));
      expect(
        verification.payload?.productCode,
        equals('bdj_studio_voice_spot'),
      );
    },
  );

  test(
    'LicenseIssuer emite y valida tokens SPP3 para bdj_studio_audio_analyzer',
    () async {
      final issuer = LicenseIssuer();
      await issuer.load();

      final audioAnalyzerRecord = LicenseRecord(
        id: 'aa-12345678',
        product: 'bdj_studio_audio_analyzer',
        device: 'V1-AUDIO-ANALYZER-0001',
        plan: 'permanent',
        issuedAt: DateTime.now().toUtc(),
        customerId: 'customer-analyzer',
        customerName: 'Audio Lab Test',
        status: 'active',
        expiresAt: null,
        exactVersion: '1.0.0',
      );

      final token = await issuer.generateSpp3TokenForRecord(audioAnalyzerRecord);
      expect(token, startsWith('SPP3.'));

      final hwidHash = KeyHierarchy.hashHwid('V1-AUDIO-ANALYZER-0001');
      final verification = await Spp3Token.verify(
        token: token,
        rootPublicKeyBase64: KeyHierarchy.ecosystemRootPublicKey,
        expectedProductCode: 'bdj_studio_audio_analyzer',
        currentHwidHash: hwidHash,
        expectedVersion: '1.0.0',
      );

      expect(verification.status, equals(Spp3VerificationStatus.valid));
      expect(
        verification.payload?.productCode,
        equals('bdj_studio_audio_analyzer'),
      );
      expect(verification.payload?.exactVersion, equals('1.0.0'));
    },
  );
}
