import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../main.dart';

class SupabaseService {
  static const String supabaseUrl = 'https://kunogcxhtsnsslmhdfny.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt1bm9nY3hodHNuc3NsbWhkZm55Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg1MzgzMzUsImV4cCI6MjEwNDExNDMzNX0.xHap9J-jRONSonQ-XXGgboShBGLponCs3yFOkZFc-Rw';

  static const Duration _timeout = Duration(seconds: 5);

  Map<String, String> get _headers => {
    'apikey': supabaseAnonKey,
    'Authorization': 'Bearer $supabaseAnonKey',
    'Content-Type': 'application/json',
    'Prefer': 'resolution=merge-duplicates,return=representation',
  };

  Future<List<CustomerRecord>?> fetchCustomers() async {
    try {
      final uri = Uri.parse('$supabaseUrl/rest/v1/customers?select=*&order=created_at.asc');
      final res = await http.get(uri, headers: _headers).timeout(_timeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List;
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
    } catch (e) {
      debugPrint('Supabase fetchCustomers error: $e');
    }
    return null;
  }

  Future<void> syncCustomer(CustomerRecord customer) async {
    try {
      final uri = Uri.parse('$supabaseUrl/rest/v1/customers');
      await http.post(
        uri,
        headers: _headers,
        body: jsonEncode({
          'id': customer.id,
          'name': customer.name,
          'email': customer.email,
          'device': customer.device,
          'created_at': customer.createdAt.toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }),
      ).timeout(_timeout);
    } catch (e) {
      debugPrint('Supabase syncCustomer error: $e');
    }
  }

  Future<void> syncCustomersBulk(List<CustomerRecord> list) async {
    if (list.isEmpty) return;
    try {
      final uri = Uri.parse('$supabaseUrl/rest/v1/customers');
      final body = list.map((customer) => {
        'id': customer.id,
        'name': customer.name,
        'email': customer.email,
        'device': customer.device,
        'created_at': customer.createdAt.toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).toList();
      await http.post(uri, headers: _headers, body: jsonEncode(body)).timeout(_timeout);
    } catch (e) {
      debugPrint('Supabase syncCustomersBulk error: $e');
    }
  }

  Future<void> deleteCustomer(String customerId, {String? device}) async {
    try {
      final uriCust = Uri.parse('$supabaseUrl/rest/v1/customers?id=eq.${Uri.encodeComponent(customerId)}');
      await http.delete(uriCust, headers: _headers).timeout(_timeout);
      final uriLic = Uri.parse('$supabaseUrl/rest/v1/licenses?customer_id=eq.${Uri.encodeComponent(customerId)}');
      await http.delete(uriLic, headers: _headers).timeout(_timeout);
      if (device != null && device.trim().isNotEmpty) {
        final uriLicDev = Uri.parse('$supabaseUrl/rest/v1/licenses?device=eq.${Uri.encodeComponent(device.trim())}');
        await http.delete(uriLicDev, headers: _headers).timeout(_timeout);
      }
    } catch (e) {
      debugPrint('Supabase deleteCustomer error: $e');
    }
  }

  Future<List<LicenseRecord>?> fetchLicenses() async {
    try {
      final uri = Uri.parse('$supabaseUrl/rest/v1/licenses?select=*&order=issued_at.asc');
      final res = await http.get(uri, headers: _headers).timeout(_timeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List;
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
    } catch (e) {
      debugPrint('Supabase fetchLicenses error: $e');
    }
    return null;
  }

  Future<void> syncLicense(LicenseRecord license) async {
    try {
      final uri = Uri.parse('$supabaseUrl/rest/v1/licenses');
      await http.post(
        uri,
        headers: _headers,
        body: jsonEncode({
          'id': license.id,
          'customer_id': license.customerId,
          'customer_name': license.customerName,
          'product': license.product,
          'device': license.device,
          'plan': license.plan,
          'token': license.token,
          'status': license.status,
          'issued_at': license.issuedAt.toIso8601String(),
          'expires_at': license.expiresAt?.toIso8601String(),
          'exact_version': license.exactVersion,
          'hwid_schema_version': license.hwidSchemaVersion,
          'issued_by': license.issuedBy,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }),
      ).timeout(_timeout);
    } catch (e) {
      debugPrint('Supabase syncLicense error: $e');
    }
  }

  Future<void> syncLicensesBulk(List<LicenseRecord> list) async {
    if (list.isEmpty) return;
    try {
      final uri = Uri.parse('$supabaseUrl/rest/v1/licenses');
      final body = list.map((license) => {
        'id': license.id,
        'customer_id': license.customerId,
        'customer_name': license.customerName,
        'product': license.product,
        'device': license.device,
        'plan': license.plan,
        'token': license.token,
        'status': license.status,
        'issued_at': license.issuedAt.toIso8601String(),
        'expires_at': license.expiresAt?.toIso8601String(),
        'exact_version': license.exactVersion,
        'hwid_schema_version': license.hwidSchemaVersion,
        'issued_by': license.issuedBy,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).toList();
      await http.post(uri, headers: _headers, body: jsonEncode(body)).timeout(_timeout);
    } catch (e) {
      debugPrint('Supabase syncLicensesBulk error: $e');
    }
  }

  Future<void> deleteLicense(String licenseId) async {
    try {
      final uri = Uri.parse('$supabaseUrl/rest/v1/licenses?id=eq.${Uri.encodeComponent(licenseId)}');
      await http.delete(uri, headers: _headers).timeout(_timeout);
    } catch (e) {
      debugPrint('Supabase deleteLicense error: $e');
    }
  }

  Future<List<BlockedDeviceRecord>?> fetchBlockedDevices() async {
    try {
      final uri = Uri.parse('$supabaseUrl/rest/v1/blocked_devices?select=*');
      final res = await http.get(uri, headers: _headers).timeout(_timeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List;
        return data.map((item) {
          final m = item as Map<String, dynamic>;
          return BlockedDeviceRecord(
            device: m['device'] as String,
            reason: m['reason'] as String,
            blockedAt: DateTime.parse(m['blocked_at'] as String),
            customerId: m['customer_id'] as String?,
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('Supabase fetchBlockedDevices error: $e');
    }
    return null;
  }

  Future<void> syncBlockedDevice(BlockedDeviceRecord block) async {
    try {
      final uri = Uri.parse('$supabaseUrl/rest/v1/blocked_devices');
      await http.post(
        uri,
        headers: _headers,
        body: jsonEncode({
          'device': block.device,
          'reason': block.reason,
          'blocked_at': block.blockedAt.toIso8601String(),
          'customer_id': block.customerId,
        }),
      ).timeout(_timeout);
    } catch (e) {
      debugPrint('Supabase syncBlockedDevice error: $e');
    }
  }

  Future<void> syncBlockedDevicesBulk(List<BlockedDeviceRecord> list) async {
    if (list.isEmpty) return;
    try {
      final uri = Uri.parse('$supabaseUrl/rest/v1/blocked_devices');
      final body = list.map((block) => {
        'device': block.device,
        'reason': block.reason,
        'blocked_at': block.blockedAt.toIso8601String(),
        'customer_id': block.customerId,
      }).toList();
      await http.post(uri, headers: _headers, body: jsonEncode(body)).timeout(_timeout);
    } catch (e) {
      debugPrint('Supabase syncBlockedDevicesBulk error: $e');
    }
  }

  Future<void> deleteBlockedDevice(String device) async {
    try {
      final uri = Uri.parse('$supabaseUrl/rest/v1/blocked_devices?device=eq.${Uri.encodeComponent(device)}');
      await http.delete(uri, headers: _headers).timeout(_timeout);
    } catch (e) {
      debugPrint('Supabase deleteBlockedDevice error: $e');
    }
  }

  Future<List<AdminAccount>?> fetchAdmins() async {
    try {
      final uri = Uri.parse('$supabaseUrl/rest/v1/admin_accounts?select=*');
      final res = await http.get(uri, headers: _headers).timeout(_timeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List;
        return data.map((item) {
          final m = item as Map<String, dynamic>;
          return AdminAccount(
            id: m['id'] as String?,
            email: m['email'] as String,
            passwordHash: m['password_hash'] as String,
            passwordSalt: m['password_salt'] as String?,
            role: m['role'] as String? ?? 'super',
            isActive: m['is_active'] as bool? ?? true,
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('Supabase fetchAdmins error: $e');
    }
    return null;
  }

  Future<void> syncAdmin(AdminAccount admin) async {
    try {
      final uri = Uri.parse('$supabaseUrl/rest/v1/admin_accounts');
      await http.post(
        uri,
        headers: _headers,
        body: jsonEncode({
          'id': admin.id ?? admin.email,
          'email': admin.email.trim().toLowerCase(),
          'password_hash': admin.passwordHash,
          'password_salt': admin.passwordSalt ?? '',
          'role': admin.role,
          'is_active': admin.isActive,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }),
      ).timeout(_timeout);
    } catch (e) {
      debugPrint('Supabase syncAdmin error: $e');
    }
  }

  Future<void> syncAdminsBulk(List<AdminAccount> list) async {
    if (list.isEmpty) return;
    try {
      final uri = Uri.parse('$supabaseUrl/rest/v1/admin_accounts');
      final body = list.map((admin) => {
        'id': admin.id ?? admin.email,
        'email': admin.email.trim().toLowerCase(),
        'password_hash': admin.passwordHash,
        'password_salt': admin.passwordSalt ?? '',
        'role': admin.role,
        'is_active': admin.isActive,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).toList();
      await http.post(uri, headers: _headers, body: jsonEncode(body)).timeout(_timeout);
    } catch (e) {
      debugPrint('Supabase syncAdminsBulk error: $e');
    }
  }

  Future<void> deleteAdmin(String emailOrId) async {
    try {
      final uri = Uri.parse('$supabaseUrl/rest/v1/admin_accounts?email=eq.${Uri.encodeComponent(emailOrId.toLowerCase())}');
      await http.delete(uri, headers: _headers).timeout(_timeout);
    } catch (e) {
      debugPrint('Supabase deleteAdmin error: $e');
    }
  }
}
