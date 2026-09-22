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

  test('customer records preserve serialization and date fields', () {
    final createdAt = DateTime.utc(2026, 7, 22, 13);
    final customer = CustomerRecord(
      id: 'customer-1',
      name: 'DJ David',
      email: 'david@example.com',
      device: 'DEVICE-ABC-123',
      createdAt: createdAt,
    );
    final restored = CustomerRecord.fromJson(customer.toJson());

    expect(restored.id, 'customer-1');
    expect(restored.name, 'DJ David');
    expect(restored.email, 'david@example.com');
    expect(restored.device, 'DEVICE-ABC-123');
    expect(restored.createdAt, createdAt);
  });
}
