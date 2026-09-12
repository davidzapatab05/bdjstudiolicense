import 'package:bdj_studio_license/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('license plans keep the commercial durations', () {
    expect(LicensePlan.trial7.days, 7);
    expect(LicensePlan.month.days, 30);
    expect(LicensePlan.halfYear.days, 180);
    expect(LicensePlan.year.days, 365);
    expect(LicensePlan.permanent.days, isNull);
  });

  test('license records preserve production audit fields', () {
    final issuedAt = DateTime.utc(2026, 7, 22, 12);
    final expiresAt = DateTime.utc(2027, 7, 22, 12);
    final record = LicenseRecord(
      id: 'unique-license-id',
      product: 'bdj_studio_sample_pad',
      device: 'device-fingerprint-123',
      plan: LicensePlan.year.name,
      issuedAt: issuedAt,
      customerId: 'customer-1',
      customerName: 'Cliente de prueba',
      expiresAt: expiresAt,
      issuedBy: 'david.zapata@bdjstudio.com',
    );

    final restored = LicenseRecord.fromJson(record.toJson());

    expect(restored.id, record.id);
    expect(restored.product, record.product);
    expect(restored.device, record.device);
    expect(restored.plan, record.plan);
    expect(restored.issuedAt, issuedAt);
    expect(restored.customerId, record.customerId);
    expect(restored.customerName, record.customerName);
    expect(restored.expiresAt, expiresAt);
    expect(restored.issuedBy, 'david.zapata@bdjstudio.com');
  });

  test('blocked devices preserve cloud-ready fields and match safely', () {
    final blockedAt = DateTime.utc(2026, 7, 22, 13);
    final blocked = BlockedDeviceRecord(
      device: 'DEVICE-ABC-123',
      reason: 'Fraude confirmado',
      blockedAt: blockedAt,
      customerId: 'customer-1',
    );
    final restored = BlockedDeviceRecord.fromJson(blocked.toJson());
    final issuer = LicenseIssuer()..blockedDevices.add(restored);

    expect(restored.reason, 'Fraude confirmado');
    expect(restored.blockedAt, blockedAt);
    expect(restored.customerId, 'customer-1');
    expect(issuer.isDeviceBlocked('device-abc-123'), isTrue);
  });
}
