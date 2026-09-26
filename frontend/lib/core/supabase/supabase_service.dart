import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../../main.dart';
import '../rbac/rbac_models.dart';

/// Error devuelto por Supabase (RLS, auth o red) con mensaje legible.
class SupabaseException implements Exception {
  SupabaseException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  bool get isPermissionDenied => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

/// Sesión de Supabase Auth del usuario conectado.
class AuthSession {
  AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
    required this.email,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String userId;
  final String email;

  bool get isExpiringSoon =>
      DateTime.now().toUtc().isAfter(expiresAt.subtract(const Duration(seconds: 60)));

  factory AuthSession.fromAuthResponse(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? const {};
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
    return AuthSession(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresAt: DateTime.now().toUtc().add(Duration(seconds: expiresIn)),
      userId: user['id'] as String? ?? '',
      email: (user['email'] as String? ?? '').trim().toLowerCase(),
    );
  }

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.toIso8601String(),
        'user_id': userId,
        'email': email,
      };

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        userId: json['user_id'] as String? ?? '',
        email: json['email'] as String? ?? '',
      );
}

/// Acceso a Supabase. Toda autorización real la aplica la base de datos
/// mediante RLS (ver supabase/migrations/20260926_rbac_rls.sql); la app solo
/// oculta lo que el usuario no puede hacer.
class SupabaseService {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://kunogcxhtsnsslmhdfny.supabase.co',
  );
  // La anon key es pública por diseño: sin sesión válida RLS no permite nada.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt1bm9nY3hodHNuc3NsbWhkZm55Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg1MzgzMzUsImV4cCI6MjEwNDExNDMzNX0.xHap9J-jRONSonQ-XXGgboShBGLponCs3yFOkZFc-Rw',
  );

  static const Duration _timeout = Duration(seconds: 12);
  static const _sessionKey = 'bdj_supabase_session_v1';
  final _storage = const FlutterSecureStorage();

  AuthSession? session;

  // ------------------------------------------------------------------
  // Auth
  // ------------------------------------------------------------------

  Map<String, String> get _anonHeaders => {
        'apikey': supabaseAnonKey,
        'Content-Type': 'application/json',
      };

  Future<AuthSession> signIn(String email, String password) async {
    final res = await http
        .post(
          Uri.parse('$supabaseUrl/auth/v1/token?grant_type=password'),
          headers: _anonHeaders,
          body: jsonEncode({'email': email.trim().toLowerCase(), 'password': password}),
        )
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw SupabaseException(_authError(res), statusCode: res.statusCode);
    }
    session = AuthSession.fromAuthResponse(jsonDecode(res.body) as Map<String, dynamic>);
    await _persistSession();
    return session!;
  }

  /// Verifica credenciales sin reemplazar la sesión actual.
  Future<bool> verifyPassword(String email, String password) async {
    try {
      final res = await http
          .post(
            Uri.parse('$supabaseUrl/auth/v1/token?grant_type=password'),
            headers: _anonHeaders,
            body: jsonEncode({'email': email.trim().toLowerCase(), 'password': password}),
          )
          .timeout(_timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> restoreSession() async {
    try {
      final raw = await _storage.read(key: _sessionKey);
      if (raw == null || raw.isEmpty) return false;
      session = AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      await _ensureFreshToken();
      return session != null;
    } catch (e) {
      debugPrint('Supabase restoreSession error: $e');
      await clearSession();
      return false;
    }
  }

  Future<void> signOut() async {
    final current = session;
    if (current != null) {
      try {
        await http
            .post(
              Uri.parse('$supabaseUrl/auth/v1/logout'),
              headers: {..._anonHeaders, 'Authorization': 'Bearer ${current.accessToken}'},
            )
            .timeout(_timeout);
      } catch (_) {}
    }
    await clearSession();
  }

  Future<void> clearSession() async {
    session = null;
    await _storage.delete(key: _sessionKey);
  }

  /// Registra la cuenta de acceso de un nuevo usuario. La fila en
  /// admin_accounts se vincula sola por correo (trigger en la BD).
  Future<void> signUpUser(String email, String password) async {
    final res = await http
        .post(
          Uri.parse('$supabaseUrl/auth/v1/signup'),
          headers: _anonHeaders,
          body: jsonEncode({'email': email.trim().toLowerCase(), 'password': password}),
        )
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw SupabaseException(_authError(res), statusCode: res.statusCode);
    }
  }

  Future<void> updateOwnPassword(String newPassword) async {
    await _ensureFreshToken();
    final res = await http
        .put(
          Uri.parse('$supabaseUrl/auth/v1/user'),
          headers: _authHeaders(),
          body: jsonEncode({'password': newPassword}),
        )
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw SupabaseException(_authError(res), statusCode: res.statusCode);
    }
  }

  Future<void> _ensureFreshToken() async {
    final current = session;
    if (current == null) {
      throw SupabaseException('Sesión expirada. Inicia sesión nuevamente.', statusCode: 401);
    }
    if (!current.isExpiringSoon) return;
    final res = await http
        .post(
          Uri.parse('$supabaseUrl/auth/v1/token?grant_type=refresh_token'),
          headers: _anonHeaders,
          body: jsonEncode({'refresh_token': current.refreshToken}),
        )
        .timeout(_timeout);
    if (res.statusCode != 200) {
      await clearSession();
      throw SupabaseException('Sesión expirada. Inicia sesión nuevamente.', statusCode: 401);
    }
    session = AuthSession.fromAuthResponse(jsonDecode(res.body) as Map<String, dynamic>);
    await _persistSession();
  }

  Future<void> _persistSession() async {
    final current = session;
    if (current == null) return;
    await _storage.write(key: _sessionKey, value: jsonEncode(current.toJson()));
  }

  Map<String, String> _authHeaders({bool returnRows = false}) => {
        'apikey': supabaseAnonKey,
        'Authorization': 'Bearer ${session?.accessToken ?? ''}',
        'Content-Type': 'application/json',
        if (returnRows) 'Prefer': 'return=representation',
      };

  String _authError(http.Response res) {
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final code = body['error_code'] ?? body['error'];
      if (code == 'invalid_credentials' || code == 'invalid_grant') {
        return 'Usuario o contraseña incorrectos.';
      }
      if (code == 'email_not_confirmed') {
        return 'Confirma tu correo antes de iniciar sesión.';
      }
      if (code == 'weak_password') {
        return 'La contraseña es demasiado débil.';
      }
      return (body['msg'] ?? body['error_description'] ?? body['message'] ?? 'Error de autenticación').toString();
    } catch (_) {
      return 'Error de autenticación (${res.statusCode}).';
    }
  }

  // ------------------------------------------------------------------
  // REST (PostgREST) con token del usuario
  // ------------------------------------------------------------------

  Future<List<dynamic>> _get(String pathAndQuery) async {
    await _ensureFreshToken();
    final res = await http
        .get(Uri.parse('$supabaseUrl/rest/v1/$pathAndQuery'), headers: _authHeaders())
        .timeout(_timeout);
    _throwIfError(res);
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<void> _insert(String table, Object body) async {
    await _ensureFreshToken();
    final res = await http
        .post(
          Uri.parse('$supabaseUrl/rest/v1/$table'),
          headers: _authHeaders(returnRows: true),
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    _throwIfError(res);
  }

  /// PATCH/DELETE: RLS filtra en silencio las filas no autorizadas, por eso
  /// se exige que al menos una fila haya sido afectada.
  Future<int> _mutate(String method, String table, String filter, {Object? body, bool requireRows = true}) async {
    await _ensureFreshToken();
    final uri = Uri.parse('$supabaseUrl/rest/v1/$table?$filter');
    final headers = _authHeaders(returnRows: true);
    final res = await (method == 'PATCH'
            ? http.patch(uri, headers: headers, body: jsonEncode(body))
            : http.delete(uri, headers: headers))
        .timeout(_timeout);
    _throwIfError(res);
    final rows = res.body.isEmpty ? const [] : jsonDecode(res.body) as List<dynamic>;
    if (requireRows && rows.isEmpty) {
      throw SupabaseException(
        'No tienes permiso para esta acción o el registro ya no existe.',
        statusCode: 403,
      );
    }
    return rows.length;
  }

  void _throwIfError(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    var message = 'Error del servidor (${res.statusCode}).';
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final code = body['code'];
      if (code == '42501' || res.statusCode == 401 || res.statusCode == 403) {
        final detail = body['message']?.toString() ?? '';
        message = detail.contains('row-level security') || detail.isEmpty
            ? 'No tienes permiso para esta acción.'
            : detail;
      } else if (code == '23505') {
        message = 'El registro ya existe.';
      } else if (body['message'] != null) {
        message = body['message'].toString();
      }
    } catch (_) {}
    throw SupabaseException(message, statusCode: res.statusCode);
  }

  static String _eq(String value) => 'eq.${Uri.encodeComponent(value)}';

  // ------------------------------------------------------------------
  // Customers
  // ------------------------------------------------------------------

  Map<String, dynamic> _customerJson(CustomerRecord c) => {
        'id': c.id,
        'name': c.name,
        'email': c.email,
        'device': c.device,
        'created_at': c.createdAt.toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  Future<List<CustomerRecord>> fetchCustomers() async {
    final data = await _get('customers?select=*&order=created_at.asc');
    return data.map((item) {
      final m = item as Map<String, dynamic>;
      return CustomerRecord(
        id: m['id'] as String,
        name: m['name'] as String,
        email: m['email'] as String,
        device: m['device'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
    }).toList();
  }

  Future<void> insertCustomer(CustomerRecord customer) =>
      _insert('customers', _customerJson(customer));

  Future<void> updateCustomer(CustomerRecord customer) {
    final body = _customerJson(customer)..remove('id')..remove('created_at');
    return _mutate('PATCH', 'customers', 'id=${_eq(customer.id)}', body: body);
  }

  /// Borra el cliente y sus licencias (licencias primero por la FK).
  Future<void> deleteCustomer(String customerId, {String? device}) async {
    await _mutate('DELETE', 'licenses', 'customer_id=${_eq(customerId)}', requireRows: false);
    if (device != null && device.trim().isNotEmpty) {
      await _mutate('DELETE', 'licenses', 'device=${_eq(device.trim())}', requireRows: false);
    }
    await _mutate('DELETE', 'customers', 'id=${_eq(customerId)}');
  }

  // ------------------------------------------------------------------
  // Licenses
  // ------------------------------------------------------------------

  Map<String, dynamic> _licenseJson(LicenseRecord l) => {
        'id': l.id,
        'customer_id': l.customerId,
        'customer_name': l.customerName,
        'product': l.product,
        'device': l.device,
        'plan': l.plan,
        'token': l.token,
        'status': l.status,
        'issued_at': l.issuedAt.toIso8601String(),
        'expires_at': l.expiresAt?.toIso8601String(),
        'exact_version': l.exactVersion,
        'hwid_schema_version': l.hwidSchemaVersion,
        'issued_by': l.issuedBy,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  Future<List<LicenseRecord>> fetchLicenses() async {
    final data = await _get('licenses?select=*&order=issued_at.asc');
    return data.map((item) {
      final m = item as Map<String, dynamic>;
      return LicenseRecord(
        id: m['id'] as String,
        product: m['product'] as String,
        device: m['device'] as String,
        plan: m['plan'] as String,
        issuedAt: DateTime.parse(m['issued_at'] as String),
        customerId: m['customer_id'] as String?,
        customerName: m['customer_name'] as String?,
        token: m['token'] as String?,
        status: m['status'] as String? ?? 'active',
        expiresAt: m['expires_at'] != null ? DateTime.parse(m['expires_at'] as String) : null,
        exactVersion: m['exact_version'] as String?,
        hwidSchemaVersion: m['hwid_schema_version'] as String? ?? 'V2',
        issuedBy: m['issued_by'] as String?,
      );
    }).toList();
  }

  Future<void> insertLicense(LicenseRecord license) =>
      _insert('licenses', _licenseJson(license));

  /// Actualiza nombre de cliente u otros campos de una licencia existente.
  Future<void> patchLicense(String licenseId, Map<String, dynamic> fields) =>
      _mutate('PATCH', 'licenses', 'id=${_eq(licenseId)}', body: {
        ...fields,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

  Future<void> deleteLicense(String licenseId) =>
      _mutate('DELETE', 'licenses', 'id=${_eq(licenseId)}');

  // ------------------------------------------------------------------
  // Admin accounts & roles
  // ------------------------------------------------------------------

  /// RLS devuelve solo la fila propia salvo que el usuario tenga usuarios.read.
  Future<List<AdminAccount>> fetchAdmins() async {
    final data = await _get('admin_accounts?select=id,email,role,is_active,permissions,user_id&order=email.asc');
    return data
        .map((item) => AdminAccount.fromRemote(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> insertAdmin(AdminAccount admin) => _insert('admin_accounts', {
        'id': admin.id ?? admin.email.trim().toLowerCase(),
        'email': admin.email.trim().toLowerCase(),
        'role': admin.role,
        'permissions': admin.role == 'custom' ? admin.permissions : null,
        'is_active': admin.isActive,
      });

  Future<void> updateAdmin(String currentEmail, AdminAccount admin) =>
      _mutate('PATCH', 'admin_accounts', 'email=${_eq(currentEmail.trim().toLowerCase())}', body: {
        'email': admin.email.trim().toLowerCase(),
        'role': admin.role,
        'permissions': admin.role == 'custom' ? admin.permissions : null,
        'is_active': admin.isActive,
      });

  Future<void> deleteAdmin(String email) =>
      _mutate('DELETE', 'admin_accounts', 'email=${_eq(email.trim().toLowerCase())}');

  Future<List<AppRole>> fetchRoles() async {
    final data = await _get('roles?select=*&order=is_system.desc,name.asc');
    return data.map((item) {
      final m = item as Map<String, dynamic>;
      return AppRole.fromJson({
        'id': m['id'],
        'name': m['name'],
        'description': m['description'],
        'permissions': m['permissions'],
        'isSystem': m['is_system'],
      });
    }).toList();
  }

  Future<void> saveRole(AppRole role, {required bool exists}) {
    final body = {
      'name': role.name,
      'description': role.description,
      'permissions': role.permissions,
    };
    if (exists) {
      return _mutate('PATCH', 'roles', 'id=${_eq(role.id)}', body: body);
    }
    return _insert('roles', {'id': role.id, ...body});
  }

  Future<void> deleteRole(String roleId) =>
      _mutate('DELETE', 'roles', 'id=${_eq(roleId)}');
}
