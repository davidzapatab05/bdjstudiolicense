import 'package:bdj_studio_license/core/rbac/rbac_models.dart';
import 'package:bdj_studio_license/main.dart';
import 'package:flutter_test/flutter_test.dart';

LicenseIssuer _issuerAs(String role, {Map<String, Map<String, bool>>? perms}) {
  final issuer = LicenseIssuer()
    ..unlocked = true
    ..currentAdmin = AdminAccount(
      email: 'user@bdjstudio.com',
      role: role,
      permissions: perms,
    );
  issuer.roles.addAll(AppRole.systemRoles);
  return issuer;
}

void main() {
  test('Super Administrador: acceso total', () {
    final i = _issuerAs('super_admin');
    for (final m in ['gestion', 'usuarios']) {
      for (final a in ['create', 'read', 'update', 'delete']) {
        expect(i.canDo(m, a), isTrue, reason: '$m.$a');
      }
    }
  });

  test('Administrador de Licencias: CRUD de licencias, sin usuarios', () {
    final i = _issuerAs('license_admin');
    for (final a in ['create', 'read', 'update', 'delete']) {
      expect(i.canDo('gestion', a), isTrue, reason: 'gestion.$a');
      expect(i.canDo('usuarios', a), isFalse, reason: 'usuarios.$a');
    }
  });

  test('Operador de Licencias: solo crear y buscar', () {
    final i = _issuerAs('operator');
    expect(i.canDo('gestion', 'create'), isTrue);
    expect(i.canDo('gestion', 'read'), isTrue);
    expect(i.canDo('gestion', 'update'), isFalse);
    expect(i.canDo('gestion', 'delete'), isFalse);
    expect(i.canDo('usuarios', 'read'), isFalse);
  });

  test('Permisos editados del rol se respetan (RBAC editable)', () {
    final i = _issuerAs('license_admin');
    i.roles
      ..removeWhere((r) => r.id == 'license_admin')
      ..add(const AppRole(
        id: 'license_admin',
        name: 'Administrador de Licencias',
        description: '',
        isSystem: true,
        permissions: {
          'gestion': {'create': true, 'read': true, 'update': true, 'delete': false},
        },
      ));
    expect(i.canDo('gestion', 'delete'), isFalse);
    expect(i.canDo('gestion', 'update'), isTrue);
  });

  test('Sin sesión o cuenta inactiva: nada', () {
    final i = _issuerAs('super_admin')..unlocked = false;
    expect(i.canDo('gestion', 'read'), isFalse);
    final j = LicenseIssuer()
      ..unlocked = true
      ..currentAdmin = const AdminAccount(
        email: 'x@bdjstudio.com',
        role: 'license_admin',
        isActive: false,
      );
    expect(j.canDo('gestion', 'read'), isFalse);
  });

  test('Alias antiguo "super" se normaliza', () {
    expect(AdminAccount.normalizeRole('super'), 'super_admin');
    expect(
      AdminAccount.fromRemote({'email': 'A@B.com', 'role': 'super'}).role,
      'super_admin',
    );
  });
}
