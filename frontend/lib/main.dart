import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:bdj_license_core/bdj_license_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/filesystem/app_storage_service.dart';
import 'core/security/keychain_ci_smoke.dart';
import 'core/supabase/supabase_service.dart';
import 'core/rbac/rbac_models.dart';

part 'dashboard.dart';

String _shortDeviceId(String value) {
  final normalized = value.trim();
  if (normalized.length <= 18) return normalized;
  return '${normalized.substring(0, 8)}…${normalized.substring(normalized.length - 8)}';
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment(
    'BDJ_KEYCHAIN_CI_SMOKE',
    defaultValue: false,
  )) {
    await runKeychainCiSmokeTest();
    return;
  }
  await _clearIssuerDataAfterReinstall();
  await AppStorageService.initialize();
  final issuer = LicenseIssuer();
  await issuer.load();
  runApp(LicenseApp(issuer));
}

const _installationMarker = 'bdj_license_installation_v1';

/// En Apple el Keychain no se borra al desinstalar. El estado de emisión no
/// debe reaparecer tras una instalación limpia de BDJ Studio License.
Future<void> _clearIssuerDataAfterReinstall() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.containsKey(_installationMarker)) return;
  const storage = FlutterSecureStorage();
  if (await storage.read(key: 'bdj_ed25519_private') != null) {
    await prefs.setBool(_installationMarker, true);
    return;
  }
  await AppStorageService.clearPersistentData();
  await storage.deleteAll();
  await prefs.setBool(_installationMarker, true);
}

class LicenseApp extends StatelessWidget {
  const LicenseApp(this.issuer, {super.key});
  final LicenseIssuer issuer;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      splashFactory: NoSplash.splashFactory,
      // ── Paleta unificada BDJ Studio ──
      scaffoldBackgroundColor: const Color(0xFF0A0C10),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF7C4DFF),
        brightness: Brightness.dark,
        surface: const Color(0xFF141822),
      ),
      cupertinoOverrideTheme: const CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: Color(0xFF00E5FF),
        scaffoldBackgroundColor: Color(0xFF0A0C10),
        barBackgroundColor: Color(0xF20E121B),
        textTheme: CupertinoTextThemeData(
          primaryColor: Colors.white,
          textStyle: TextStyle(color: Colors.white),
        ),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Color(0xFF0E121B),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF141822),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF1E2530), width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E2430),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF141822),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF1E2530), width: 1),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    ),
    home: LicenseHome(issuer),
  );
}

class LicenseHome extends StatefulWidget {
  const LicenseHome(this.issuer, {super.key});
  final LicenseIssuer issuer;
  @override
  State<LicenseHome> createState() => _LicenseHomeState();
}

class _LicenseHomeState extends State<LicenseHome> with WidgetsBindingObserver {
  final email = TextEditingController();
  final password = TextEditingController();
  final adminEmail = TextEditingController();
  final adminPassword = TextEditingController();
  final customerSearch = TextEditingController();
  var obscurePassword = true;
  var usersSubTab = 0; // 0: Usuarios, 1: Roles y Permisos
  var obscureAdminPassword = true;
  var selectedSection = 0;
  var customerPage = 0;
  String? error;
  bool isProcessing = false;
  String processingMessage = '';
  Timer? _liveSyncTimer;
  String selectedNewAdminRole = 'operator';
  Map<String, Map<String, bool>> newAdminPermissions = AdminAccount.operatorPermissions();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startLiveAutoSync();
  }

  void _startLiveAutoSync() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = Timer.periodic(const Duration(seconds: 35), (_) async {
      if (!mounted || !widget.issuer.unlocked || widget.issuer.isSyncing) return;
      await widget.issuer.syncWithCloud();
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.issuer.unlocked && !widget.issuer.isSyncing) {
      widget.issuer.syncWithCloud().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _liveSyncTimer?.cancel();
    email.dispose();
    password.dispose();
    adminEmail.dispose();
    adminPassword.dispose();
    customerSearch.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (isProcessing) return;
    setState(() {
      isProcessing = true;
      processingMessage = 'Iniciando sesión...';
      error = null;
    });
    try {
      if (!await widget.issuer.login(email.text.trim(), password.text)) {
        setState(() => error = 'Usuario o contraseña incorrectos.');
        return;
      }
      setState(() => error = null);
    } on Object catch (exception) {
      setState(() => error = exception.toString());
    } finally {
      if (mounted) {
        setState(() => isProcessing = false);
      }
    }
  }

  Future<void> provision() async {
    if (isProcessing) return;
    setState(() {
      isProcessing = true;
      processingMessage = 'Configurando cuenta principal...';
      error = null;
    });
    try {
      await widget.issuer.initializeInitialOwner(
        email: email.text,
        password: password.text,
      );
      setState(() => error = null);
    } on Object catch (exception) {
      setState(() => error = exception.toString());
    } finally {
      if (mounted) {
        setState(() => isProcessing = false);
      }
    }
  }

  Future<void> addAdmin() async {
    if (isProcessing) return;
    setState(() {
      isProcessing = true;
      processingMessage = 'Creando usuario...';
    });
    try {
      final roleObj = widget.issuer.findRole(selectedNewAdminRole);
      final rolePerms = selectedNewAdminRole == 'custom'
          ? Map<String, Map<String, bool>>.from(
              newAdminPermissions.map((k, v) => MapEntry(k, Map<String, bool>.from(v))),
            )
          : roleObj.permissions;

      await widget.issuer.addAdmin(
        adminEmail.text.trim(),
        adminPassword.text,
        role: selectedNewAdminRole,
        permissions: rolePerms,
      );
      adminEmail.clear();
      adminPassword.clear();
      setState(() {
        error = null;
        selectedNewAdminRole = 'operator';
        newAdminPermissions = AdminAccount.operatorPermissions();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Usuario creado y sincronizado correctamente.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on Object catch (exception) {
      setState(() => error = exception.toString());
    } finally {
      if (mounted) {
        setState(() => isProcessing = false);
      }
    }
  }

  void logout() {
    widget.issuer.logout();
    password.clear();
    error = null;
    selectedSection = 0;
    setState(() {});
  }

  void updateDashboard(VoidCallback update) => setState(update);

  Future<T> runWithLoading<T>({
    required String message,
    required Future<T> Function() action,
  }) async {
    if (isProcessing) {
      return await action();
    }
    setState(() {
      isProcessing = true;
      processingMessage = message;
      error = null;
    });
    try {
      return await action();
    } finally {
      if (mounted) {
        setState(() {
          isProcessing = false;
        });
      }
    }
  }

  Widget buildLogin(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BDJ Studio License')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: max(0, constraints.maxHeight - 48).toDouble(),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(
                        MediaQuery.sizeOf(context).width < 500 ? 24 : 36,
                      ),
                      child: AutofillGroup(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Align(
                              alignment: Alignment.center,
                              child: CircleAvatar(
                                radius: 32,
                                backgroundColor: Color(0x337C4DFF),
                                child: Icon(
                                  CupertinoIcons.lock_shield_fill,
                                  size: 34,
                                  color: Color(0xFF00E5FF),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Iniciar sesi\u00f3n',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Ingresa con tu usuario y contrase\u00f1a.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: Colors.white60),
                            ),
                            const SizedBox(height: 28),
                            TextField(
                              controller: email,
                              enabled: !isProcessing,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.username],
                              decoration: const InputDecoration(
                                labelText: 'Usuario',
                                prefixIcon: Icon(CupertinoIcons.person_fill),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: password,
                              enabled: !isProcessing,
                              obscureText: obscurePassword,
                              autofillHints: const [AutofillHints.password],
                              onSubmitted: (_) =>
                                  isProcessing ? null : submit(),
                              decoration: InputDecoration(
                                labelText: 'Contraseña',
                                prefixIcon: const Icon(
                                  CupertinoIcons.lock_fill,
                                ),
                                suffixIcon: IconButton(
                                  tooltip: obscurePassword
                                      ? 'Mostrar contraseña'
                                      : 'Ocultar contraseña',
                                  onPressed: () => setState(
                                    () => obscurePassword = !obscurePassword,
                                  ),
                                  icon: Icon(
                                    obscurePassword
                                        ? CupertinoIcons.eye_fill
                                        : CupertinoIcons.eye_slash_fill,
                                  ),
                                ),
                              ),
                            ),
                            if (error != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.redAccent),
                              ),
                            ],
                            const SizedBox(height: 24),
                            SizedBox(
                              height: 52,
                              child: FilledButton.icon(
                                onPressed: isProcessing ? null : submit,
                                icon: const Icon(CupertinoIcons.arrow_right),
                                label: const Text('Iniciar sesión'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildProvisioning(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BDJ Studio License')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        CupertinoIcons.shield_lefthalf_fill,
                        color: Color(0xFF00E5FF),
                        size: 42,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Configuración de seguridad',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Ingresa los datos del administrador para proteger el sistema.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: email,
                        enabled: !isProcessing,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Correo electrónico',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: password,
                        enabled: !isProcessing,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Contraseña de seguridad',
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ],
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: isProcessing ? null : provision,
                        icon: const Icon(CupertinoIcons.lock_fill),
                        label: const Text('Guardar y continuar'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    if (!isProcessing) return const SizedBox.shrink();
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.7),
        child: Center(
          child: Card(
            color: const Color(0xFF1E1E2C),
            elevation: 12,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                    color: Color(0xFF00E5FF),
                    strokeWidth: 3,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    processingMessage.isEmpty
                        ? 'Procesando solicitud...'
                        : processingMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Por favor espera un momento...',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locked = !widget.issuer.unlocked;
    return Stack(
      children: [
        locked ? buildLogin(context) : buildDashboardShell(context),
        _buildLoadingOverlay(),
      ],
    );
  }
}

enum LicensePlan {
  trial7('7 dias', 7),
  month('1 mes', 30),
  halfYear('6 meses', 180),
  year('1 año', 365),
  custom('Personalizado', null),
  permanent('Permanente', null);

  const LicensePlan(this.label, this.days);
  final String label;
  final int? days;
}

class LicenseIssuer {
  static const expectedProductionPublicKey = String.fromEnvironment(
    'BDJ_ISSUER_PUBLIC_KEY',
    defaultValue: 'FAmmTpe5dhEDxohjQBTjB-Dvr4IR1vyfvHBkWQUp6-U=',
  );
  static const _pinHashKey = 'issuer_pin_v2';
  static const _pinSaltKey = 'issuer_pin_salt';
  static const _legacyPinKey = 'issuer_pin';
  static const _failedAttemptsKey = 'issuer_failed_attempts';
  static const _lockedUntilKey = 'issuer_locked_until';
  static const _recordsKey = 'issuer_license_records_v1';
  static const _customersKey = 'issuer_customers_v1';
  static const _adminsKey = 'issuer_admins_v1';
  static const _testAdminsMigrationKey = 'issuer_test_admins_v2';
  static const _currentSessionEmailKey = 'issuer_session_email_v1';
  static const _sessionTokenKey = 'issuer_session_auth_token_v2';
  static const _maxAttempts = 5;
  static const _pbkdf2Iterations = 210000;
  static const _bootstrapFileName = 'issuer.private.json';

  final storage = const FlutterSecureStorage();
  SharedPreferences? prefs;
  String privateKey = '';
  String publicKey = '';
  SimpleKeyPair? _operatorKeyPair;
  AdminCertificate? _adminCertificate;
  bool unlocked = false;
  String? currentUser;
  String? currentRole;

  /// Roles cargados desde la tabla `roles` de Supabase (fuente de verdad).
  final List<AppRole> roles = [];

  /// Cuenta del usuario conectado (fila propia de admin_accounts).
  AdminAccount? currentAdmin;

  /// Roles seleccionables en la UI ('custom' se muestra como opción aparte).
  List<AppRole> get allRoles {
    final source = roles.isNotEmpty ? roles : AppRole.systemRoles;
    return source.where((r) => r.id != 'custom').toList();
  }

  /// Compatibilidad con la UI previa.
  List<AppRole> get customRoles => roles.where((r) => !r.isSystem).toList();

  bool get isSuperAdmin => currentAdmin?.role == 'super_admin';

  AppRole findRole(String roleId) {
    final id = AdminAccount.normalizeRole(roleId);
    for (final r in [...roles, ...AppRole.systemRoles]) {
      if (r.id == id) return r;
    }
    return AppRole.operator;
  }

  Future<void> saveCustomRole(AppRole role) async {
    if (!isSuperAdmin) {
      throw StateError('Solo el Super Administrador puede editar roles.');
    }
    if (role.id == 'super_admin' || role.id == 'custom') {
      throw StateError('Este rol no se puede editar.');
    }
    final exists = roles.any((r) => r.id == role.id);
    await supabase.saveRole(role, exists: exists);
    await _refreshRoles();
  }

  Future<void> deleteCustomRole(String roleId) async {
    if (!isSuperAdmin) {
      throw StateError('Solo el Super Administrador puede eliminar roles.');
    }
    await supabase.deleteRole(roleId);
    await _refreshRoles();
  }

  Future<void> _refreshRoles() async {
    final fetched = await supabase.fetchRoles();
    roles
      ..clear()
      ..addAll(fetched);
  }

  /// Permiso efectivo del usuario conectado. Es solo para la UI: la base de
  /// datos vuelve a validar cada operación con RLS (has_perm).
  bool canDo(String module, String action) {
    final admin = currentAdmin;
    if (!unlocked || admin == null || !admin.isActive) return false;
    final m = module == 'admins' ? 'usuarios' : module;
    if (admin.role == 'super_admin') return true;
    if (admin.role == 'custom') {
      return admin.permissions?[m]?[action] ?? false;
    }
    return findRole(admin.role).hasPermission(m, action);
  }

  void _requirePermission(String module, String action, String message) {
    if (!canDo(module, action)) throw StateError(message);
  }

  final List<LicenseRecord> records = [];
  final List<CustomerRecord> customers = [];
  final List<AdminAccount> admins = [];
  final supabase = SupabaseService();
  bool isSyncing = false;
  bool get isConfigured => privateKey.isNotEmpty && publicKey.isNotEmpty;

  bool get needsProvisioning => false;
  Future<void> load() async {
    prefs = await SharedPreferences.getInstance();
    final storedPriv = await storage.read(key: 'bdj_spp3_op_private');
    final storedPub = await storage.read(key: 'bdj_spp3_op_public');
    final storedCert = await storage.read(key: 'bdj_spp3_admin_cert');

    if (storedPriv != null && storedPub != null && storedCert != null) {
      try {
        final seedBytes = base64Url.decode(storedPriv);
        _operatorKeyPair = await KeyHierarchy.generateKeyPairFromSeed(
          seedBytes,
        );
        _adminCertificate = AdminCertificate.fromEncodedString(storedCert);
        privateKey = storedPriv;
        publicKey = storedPub;
      } catch (_) {}
    }

    if (_operatorKeyPair == null ||
        _adminCertificate == null ||
        _adminCertificate!.isExpired) {
      await _provisionSpp3OperatorKeys();
    }
    // Todo vive en Supabase: se purgan restos de versiones anteriores
    // (incluidas cuentas y sesiones locales con hash de contraseña).
    for (final key in [
      _recordsKey,
      _customersKey,
      _adminsKey,
      'issuer_sync_queue_v1',
      _currentSessionEmailKey,
      _sessionTokenKey,
      _testAdminsMigrationKey,
      'issuer_custom_roles_v1',
    ]) {
      await prefs?.remove(key);
    }

    records.clear();
    customers.clear();
    admins.clear();

    // Restaurar sesión de Supabase Auth (si existe y sigue vigente)
    try {
      if (await supabase.restoreSession()) {
        if (await _loadCurrentAdmin()) {
          unlocked = true;
          await syncWithCloud();
        } else {
          await supabase.signOut();
        }
      }
    } catch (e) {
      // Sin conexión al iniciar: se mostrará el login.
      debugPrint('No se pudo restaurar la sesión: $e');
    }
  }

  /// Carga la fila propia de admin_accounts y el catálogo de roles.
  /// Devuelve false si el usuario no tiene cuenta activa en la consola.
  Future<bool> _loadCurrentAdmin() async {
    final session = supabase.session;
    if (session == null) return false;
    try {
      final visible = await supabase.fetchAdmins();
      final me = visible.cast<AdminAccount?>().firstWhere(
            (a) => a!.email == session.email,
            orElse: () => null,
          );
      if (me == null || !me.isActive) {
        _clearIdentity();
        return false;
      }
      currentAdmin = me;
      currentUser = me.email;
      currentRole = me.role;
      await _refreshRoles();
      admins
        ..clear()
        ..addAll(canDo('usuarios', 'read') ? visible : [me]);
      return true;
    } on SupabaseException catch (e) {
      // Solo un rechazo de autorización cierra la sesión; un fallo de red
      // se propaga para no expulsar al usuario por una caída momentánea.
      if (e.isPermissionDenied) {
        _clearIdentity();
        return false;
      }
      rethrow;
    }
  }

  void _clearIdentity() {
    unlocked = false;
    currentAdmin = null;
    currentUser = null;
    currentRole = null;
    records.clear();
    customers.clear();
    admins.clear();
    roles.clear();
  }

  Future<void> syncWithCloud() async {
    if (isSyncing || !unlocked) return;
    isSyncing = true;
    try {
      // Revalida la cuenta en cada sincronización: si fue desactivada,
      // eliminada o cambió de rol, se aplica de inmediato.
      if (!await _loadCurrentAdmin()) {
        await supabase.signOut();
        _clearIdentity();
        return;
      }
      if (!canDo('gestion', 'read')) {
        records.clear();
        customers.clear();
        return;
      }
      final results = await Future.wait([
        supabase.fetchCustomers(),
        supabase.fetchLicenses(),
      ]);
      customers
        ..clear()
        ..addAll(results[0] as List<CustomerRecord>);
      records
        ..clear()
        ..addAll(results[1] as List<LicenseRecord>);
    } catch (e) {
      debugPrint('Error en syncWithCloud: $e');
    } finally {
      isSyncing = false;
    }
  }

  // ignore: unused_element
  /// Instala material de firma una sola vez desde el archivo que acompana al
  /// instalador de superadministradores. La interfaz publica nunca muestra ni
  /// solicita la semilla; el archivo debe conservarse fuera del equipo tras la
  /// instalacion. Sample Pad no recibe esta clave privada.
  // ignore: unused_element
  Future<void> _importBootstrapKeyIfPresent() async {
    if (kIsWeb) return;
    final executable = File(Platform.resolvedExecutable);
    final bootstrap = File(
      '${executable.parent.path}${Platform.pathSeparator}$_bootstrapFileName',
    );
    if (!await bootstrap.exists()) return;
    try {
      final data =
          jsonDecode(await bootstrap.readAsString()) as Map<String, dynamic>;
      final seedText = data['privateKey'];
      if (seedText is! String) return;
      final seed = base64Url.decode(seedText);
      if (seed.length != 32) return;
      final pair = await Ed25519().newKeyPairFromSeed(seed);
      final derivedPublicKey = base64UrlEncode(
        (await pair.extractPublicKey()).bytes,
      );
      if (expectedProductionPublicKey.isEmpty ||
          !_constantTimeEquals(
            utf8.encode(derivedPublicKey),
            utf8.encode(expectedProductionPublicKey),
          )) {
        return;
      }
      // Una instalacion anterior podía conservar una clave obsoleta. Solo se
      // reemplaza cuando falta configuracion o cuando la clave publica no
      // coincide con el build SPP3 actual; los registros y clientes locales
      // permanecen intactos.
      if (privateKey.isEmpty ||
          publicKey.isEmpty ||
          !_constantTimeEquals(
            utf8.encode(publicKey),
            utf8.encode(derivedPublicKey),
          )) {
        privateKey = seedText;
        publicKey = derivedPublicKey;
        await storage.write(key: 'bdj_ed25519_private', value: privateKey);
        await storage.write(key: 'bdj_ed25519_public', value: publicKey);
      }
      await _importBootstrapAdmin(
        data['admin'],
        replaceExisting: data['replaceAdmin'] == true,
      );
      // El archivo junto al ejecutable es solo un bootstrap de primer inicio.
      // La copia maestra permanece fuera del instalador, en custodia del dueño.
      try {
        await bootstrap.delete();
      } on FileSystemException {
        // Si Windows lo esta usando, no se bloquea el inicio; el operador
        // debe retirarlo manualmente tras comprobar que la consola inicia.
      }
    } on Object {
      // Un archivo de bootstrap invalido no impide mostrar el login.
    }
  }

  /// Importa una cuenta ya hasheada incluida en el bootstrap de primer inicio.
  /// Nunca se guarda una contrasena en texto plano junto a la clave de firma.
  Future<void> _importBootstrapAdmin(
    Object? value, {
    required bool replaceExisting,
  }) async {
    if ((!replaceExisting && admins.isNotEmpty) || value is! Map) return;
    final data = Map<String, dynamic>.from(value);
    final email = data['email'];
    final passwordHash = data['passwordHash'];
    final passwordSalt = data['passwordSalt'];
    if (email is! String ||
        passwordHash is! String ||
        passwordSalt is! String ||
        !email.contains('@')) {
      return;
    }
    try {
      if (base64Url.decode(passwordHash).length != 32 ||
          base64Url.decode(passwordSalt).length < 16) {
        return;
      }
    } on FormatException {
      return;
    }
    if (replaceExisting) admins.clear();
    admins.add(
      AdminAccount(
        email: email.trim().toLowerCase(),
        passwordHash: passwordHash,
        passwordSalt: passwordSalt,
        role: 'super_admin',
      ),
    );
    await prefs!.setStringList(
      _adminsKey,
      admins.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  Future<void> _provisionSpp3OperatorKeys() async {
    final rootSeedBytes = base64Url.decode(
      'QkRKX1NUVURJT19TUFAzX1JPT1RfU0VDUkVUXzIwMjY=',
    );
    final rootKeyPair = await KeyHierarchy.generateKeyPairFromSeed(
      rootSeedBytes,
    );

    List<int>? opSeedBytes;
    final existingPriv = await storage.read(key: 'bdj_spp3_op_private');
    if (existingPriv != null && existingPriv.isNotEmpty) {
      try {
        opSeedBytes = base64Url.decode(existingPriv);
      } catch (_) {}
    }
    opSeedBytes ??= List<int>.generate(32, (_) => Random.secure().nextInt(256));

    _operatorKeyPair = await KeyHierarchy.generateKeyPairFromSeed(opSeedBytes);
    final opPub = await _operatorKeyPair!.extractPublicKey();
    final opPubStr = base64UrlEncode(opPub.bytes);
    final opPrivStr = base64UrlEncode(opSeedBytes);

    final cert = await KeyHierarchy.issueAdminCertificate(
      adminId: currentUser ?? 'propietario@bdjstudio.com',
      operatorPublicKeyBase64: opPubStr,
      rootKeyPair: rootKeyPair,
      validityDuration: const Duration(days: 365),
    );

    _adminCertificate = cert;
    privateKey = opPrivStr;
    publicKey = opPubStr;
    await storage.write(key: 'bdj_spp3_op_private', value: opPrivStr);
    await storage.write(key: 'bdj_spp3_op_public', value: opPubStr);
    await storage.write(
      key: 'bdj_spp3_admin_cert',
      value: cert.toEncodedString(),
    );
  }

  /// Inicio de sesión con Supabase Auth. El rol y los permisos se leen de la
  /// base de datos; no existe ninguna cuenta ni contraseña en el binario.
  Future<bool> login(String email, String password) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (!normalizedEmail.contains('@') || password.isEmpty) return false;
    try {
      await supabase.signIn(normalizedEmail, password);
    } on SupabaseException catch (e) {
      if (e.statusCode == 400 && e.message.contains('incorrectos')) return false;
      rethrow;
    }
    if (!await _loadCurrentAdmin()) {
      await supabase.signOut();
      throw StateError(
        'Tu cuenta no tiene acceso a la consola o está desactivada. Contacta al Super Administrador.',
      );
    }
    unlocked = true;
    await _resetFailures();
    await syncWithCloud();
    return true;
  }

  /// Ya no se crean cuentas locales: el primer Super Administrador se define
  /// en la base de datos (migración SQL) y se registra en Supabase Auth.
  Future<void> initializeInitialOwner({
    required String email,
    required String password,
  }) async {
    throw StateError(
      'La cuenta principal se configura en Supabase (ver supabase/README_RBAC.md).',
    );
  }

  Future<void> addAdmin(String email, String password, {String role = 'operator', Map<String, Map<String, bool>>? permissions}) async {
    _requirePermission('usuarios', 'create', 'No tienes permiso para crear usuarios.');
    final normalized = email.trim().toLowerCase();
    final cleanRole = AdminAccount.normalizeRole(role);
    if (!normalized.contains('@')) {
      throw ArgumentError('Indica un correo válido.');
    }
    if (password.length < 8) {
      throw ArgumentError('La contraseña debe tener al menos 8 caracteres.');
    }
    if ((cleanRole == 'super_admin' || cleanRole == 'custom') && !isSuperAdmin) {
      throw StateError('Solo el Super Administrador puede asignar ese rol.');
    }
    final account = AdminAccount(
      id: normalized,
      email: normalized,
      role: cleanRole,
      isActive: true,
      permissions: cleanRole == 'custom' ? permissions : null,
    );
    // 1) Fila con el rol (RLS: usuarios.create). 2) Cuenta de acceso en Auth.
    await supabase.insertAdmin(account);
    try {
      await supabase.signUpUser(normalized, password);
    } on SupabaseException catch (e) {
      // La fila queda creada: el usuario puede registrarse luego con su correo.
      throw StateError(
        'Rol asignado, pero no se pudo crear el acceso: ${e.message}',
      );
    }
    await syncWithCloud();
  }

  Future<void> deleteAdmin(String id) async {
    _requirePermission('usuarios', 'delete', 'No tienes permiso para eliminar usuarios.');
    final normalized = id.trim().toLowerCase();
    final target = admins.cast<AdminAccount?>().firstWhere(
      (a) => a?.id?.toLowerCase() == normalized || a?.email == normalized,
      orElse: () => null,
    );
    if (target == null) throw StateError('El usuario ya no existe.');
    if (target.role == 'super_admin') {
      throw StateError('Un Super Administrador no se puede eliminar.');
    }
    if (target.email == currentUser) {
      throw StateError('No puedes eliminar tu propia cuenta.');
    }
    await supabase.deleteAdmin(target.email);
    await syncWithCloud();
  }

  Future<void> updateAdmin(
    String id, {
    required String email,
    String? password,
    String? role,
    Map<String, Map<String, bool>>? permissions,
    bool? isActive,
  }) async {
    _requirePermission('usuarios', 'update', 'No tienes permiso para editar usuarios.');
    if ((permissions != null || role != null) && !isSuperAdmin) {
      throw StateError('Solo el Super Administrador puede modificar roles o permisos.');
    }
    final key = id.trim().toLowerCase();
    final previous = admins.cast<AdminAccount?>().firstWhere(
      (a) => a?.id?.toLowerCase() == key || a?.email == key,
      orElse: () => null,
    );
    if (previous == null) throw StateError('El usuario ya no existe.');
    final newRole = AdminAccount.normalizeRole(role ?? previous.role);
    final updated = AdminAccount(
      id: previous.id,
      email: email.trim().toLowerCase(),
      role: newRole,
      isActive: isActive ?? previous.isActive,
      permissions: newRole == 'custom' ? (permissions ?? previous.permissions) : null,
    );
    await supabase.updateAdmin(previous.email, updated);
    await syncWithCloud();
  }

  /// Cambia la contraseña del usuario conectado (Supabase Auth). Restablecer
  /// la de otra persona requiere la service key, así que se hace desde el
  /// panel de Supabase (Authentication → Users).
  Future<bool> changeAdminPassword(
    String email,
    String? currentPassword,
    String newPassword,
  ) async {
    final normalized = email.trim().toLowerCase();
    if (newPassword.trim().length < 8) {
      throw ArgumentError('La nueva contraseña debe tener al menos 8 caracteres.');
    }
    if (normalized != currentUser) {
      throw StateError(
        'Para restablecer la contraseña de otro usuario usa Supabase → Authentication → Users → "Send password recovery".',
      );
    }
    if (currentPassword == null || currentPassword.isEmpty) return false;
    if (!await supabase.verifyPassword(normalized, currentPassword)) return false;
    await supabase.updateOwnPassword(newPassword.trim());
    return true;
  }

  /// Configura esta consola con material de firma creado fuera del binario.
  /// La semilla se almacena únicamente en el almacén seguro del SO y debe
  /// corresponder a la clave pública incluida en los builds de Sample Pad.
  Future<void> provision({
    required String email,
    required String password,
    required String privateKeySeed,
  }) async {
    if (expectedProductionPublicKey.isEmpty) {
      throw StateError(
        'Este instalador no fue compilado con BDJ_ISSUER_PUBLIC_KEY.',
      );
    }
    final normalizedEmail = email.trim().toLowerCase();
    if (!normalizedEmail.contains('@') || password.length < 12) {
      throw ArgumentError(
        'Indica un correo válido y una contraseña de al menos 12 caracteres.',
      );
    }

    String seedText = privateKeySeed.trim();
    try {
      final parsed = jsonDecode(seedText);
      if (parsed is Map<String, dynamic> && parsed['privateKey'] is String) {
        seedText = parsed['privateKey'] as String;
      }
    } on FormatException {
      // También se permite pegar directamente la semilla base64url.
    }

    final seed = base64Url.decode(seedText);
    if (seed.length != 32) {
      throw const FormatException('La semilla Ed25519 debe tener 32 bytes.');
    }
    final pair = await Ed25519().newKeyPairFromSeed(seed);
    final derivedPublicKey = base64UrlEncode(
      (await pair.extractPublicKey()).bytes,
    );
    if (!_constantTimeEquals(
      utf8.encode(derivedPublicKey),
      utf8.encode(expectedProductionPublicKey),
    )) {
      throw StateError(
        'La clave privada no corresponde a la clave pública de este instalador.',
      );
    }

    privateKey = seedText;
    publicKey = derivedPublicKey;
    await storage.write(key: 'bdj_ed25519_private', value: privateKey);
    await storage.write(key: 'bdj_ed25519_public', value: publicKey);
    await _savePin(password);
    await prefs!.remove(_legacyPinKey);
    // La contraseña de administración requiere un salt aleatorio diferente
    // del PIN local de desbloqueo.
    final accountSalt = List<int>.generate(
      16,
      (_) => Random.secure().nextInt(256),
    );
    admins
      ..clear()
      ..add(
        AdminAccount(
          email: normalizedEmail,
          passwordHash: base64UrlEncode(
            await _derivePin(password, accountSalt),
          ),
          passwordSalt: base64UrlEncode(accountSalt),
          role: 'super_admin',
        ),
      );
    await prefs!.setStringList(
      _adminsKey,
      admins.map((item) => jsonEncode(item.toJson())).toList(),
    );
    await _resetFailures();
    unlocked = true;
    currentUser = normalizedEmail;
    currentRole = 'super';
  }

  Future<void> logout() async {
    await supabase.signOut();
    _clearIdentity();
  }

  Future<CustomerRecord> getOrCreateCustomer(
    String name,
    String email,
    String device, {
    bool flushSync = true,
  }) async {
    if (!unlocked) throw StateError('Inicia sesion primero.');
    final normalizedName = name.trim();
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedDevice = device.trim();
    if (normalizedDevice.length < 8) {
      throw ArgumentError(
        'El ID de dispositivo debe tener al menos 8 caracteres.',
      );
    }

    // Un cliente puede adquirir licencias para varios equipos. Cada registro
    // representa un equipo concreto, por lo que el correo NO identifica
    // por sí solo al registro: solo el ID físico evita duplicados.
    final existingIndex = customers.indexWhere(
      (c) => _samePhysicalDevice(c.device, normalizedDevice),
    );

    if (existingIndex >= 0) {
      final existing = customers[existingIndex];
      final isLegacyDeviceId = RegExp(
        r'^V[1-9]\d*-[A-Z0-9-]+$',
      ).hasMatch(existing.device.toUpperCase());
      if ((_samePhysicalDevice(existing.device, normalizedDevice) ||
              isLegacyDeviceId) &&
          existing.device != normalizedDevice &&
          canDo('gestion', 'update')) {
        // Migración de ID antiguo → actual (requiere permiso de actualizar).
        final migrated = CustomerRecord(
          id: existing.id,
          name: existing.name,
          email: existing.email,
          device: normalizedDevice,
          createdAt: existing.createdAt,
        );
        await supabase.updateCustomer(migrated);
        customers[existingIndex] = migrated;
        return migrated;
      }
      return existing;
    }

    _requirePermission('gestion', 'create', 'No tienes permiso para crear clientes.');

    // Si no se especifican nombre o correo se asignan por defecto según el ID
    final resolvedName = normalizedName.isNotEmpty
        ? normalizedName
        : 'Dispositivo ${_shortDeviceId(normalizedDevice)}';
    final resolvedEmail =
        (normalizedEmail.isNotEmpty && normalizedEmail.contains('@'))
        ? normalizedEmail
        : 'device_${normalizedDevice.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase()}@bdjstudio.local';

    final newCustomer = CustomerRecord(
      id: _randomId(),
      name: resolvedName,
      email: resolvedEmail,
      device: normalizedDevice,
      createdAt: DateTime.now().toUtc(),
    );
    await supabase.insertCustomer(newCustomer);
    customers.add(newCustomer);
    return newCustomer;
  }

  Future<void> addCustomer(
    String name,
    String email,
    String device, {
    bool flushSync = true,
  }) async {
    await getOrCreateCustomer(name, email, device, flushSync: flushSync);
  }

  Future<void> deleteCustomer(String customerId) async {
    _requirePermission('gestion', 'delete', 'No tienes permiso para eliminar clientes.');

    final targetCustomer = customers.cast<CustomerRecord?>().firstWhere(
      (c) => c?.id == customerId,
      orElse: () => null,
    );
    final targetDevice = targetCustomer?.device.trim();

    await supabase.deleteCustomer(customerId, device: targetDevice);

    records.removeWhere((r) =>
        r.customerId == customerId ||
        (targetDevice != null &&
            targetDevice.isNotEmpty &&
            r.device.trim().toLowerCase() == targetDevice.toLowerCase()));
    customers.removeWhere((customer) => customer.id == customerId);
  }

  Future<void> deleteLicense(String licenseId) async {
    _requirePermission('gestion', 'delete', 'No tienes permiso para eliminar licencias.');
    await supabase.deleteLicense(licenseId);
    records.removeWhere((r) => r.id == licenseId);
  }

  Future<void> updateCustomer(
    String customerId, {
    required String name,
    required String email,
    required String device,
  }) async {
    _requirePermission('gestion', 'update', 'No tienes permiso para editar clientes.');
    if (name.trim().isEmpty ||
        !email.contains('@') ||
        device.trim().length < 8) {
      throw ArgumentError(
        'Nombre y correo válidos, e ID de dispositivo de al menos 8 caracteres, son obligatorios.',
      );
    }
    final index = customers.indexWhere((customer) => customer.id == customerId);
    if (index < 0) throw StateError('El cliente ya no existe.');
    final current = customers[index];
    final newName = name.trim();
    final updated = CustomerRecord(
      id: current.id,
      name: newName,
      email: email.trim().toLowerCase(),
      device: device.trim(),
      createdAt: current.createdAt,
    );
    await supabase.updateCustomer(updated);
    customers[index] = updated;
    // Propagar el nuevo nombre a las licencias de este cliente
    for (var i = 0; i < records.length; i++) {
      if (records[i].customerId == customerId &&
          records[i].customerName != newName) {
        await supabase.patchLicense(records[i].id, {'customer_name': newName});
        records[i] = records[i].copyWith(customerName: newName);
      }
    }
  }

  /// Deja exactamente los productos seleccionados para un dispositivo. Las
  /// licencias retiradas se eliminan (requiere permiso de eliminar).
  Future<void> setProductAccess({
    required String customerId,
    required String device,
    required Set<String> products,
    bool flushSync = true,
  }) async {
    final removed = records
        .where(
          (record) =>
              record.isActive &&
              (record.customerId == customerId ||
                  _samePhysicalDevice(record.device, device)) &&
              !products.contains(record.product),
        )
        .toList();
    if (removed.isEmpty) return;
    _requirePermission('gestion', 'delete', 'No tienes permiso para retirar licencias.');
    for (final rem in removed) {
      await supabase.deleteLicense(rem.id);
      records.removeWhere((record) => record.id == rem.id);
    }
  }



  Future<void> configure(String pin) async {
    if (pin.length < 8) {
      throw ArgumentError('El PIN debe tener al menos 8 caracteres.');
    }
    final pair = await Ed25519().newKeyPair();
    privateKey = base64UrlEncode(await pair.extractPrivateKeyBytes());
    publicKey = base64UrlEncode((await pair.extractPublicKey()).bytes);
    await storage.write(key: 'bdj_ed25519_private', value: privateKey);
    await storage.write(key: 'bdj_ed25519_public', value: publicKey);
    await _savePin(pin);
    await prefs!.remove(_legacyPinKey);
    await _resetFailures();
    unlocked = true;
  }

  Future<bool> unlock(String pin) async {
    final lockedUntil = DateTime.tryParse(
      prefs!.getString(_lockedUntilKey) ?? '',
    );
    if (lockedUntil != null && DateTime.now().toUtc().isBefore(lockedUntil)) {
      unlocked = false;
      return false;
    }

    final salt = prefs!.getString(_pinSaltKey);
    final expected = prefs!.getString(_pinHashKey);
    if (salt != null && expected != null) {
      final actual = await _derivePin(pin, base64Url.decode(salt));
      unlocked = _constantTimeEquals(base64Url.decode(expected), actual);
    } else {
      // One-time migration for consoles configured before v1.0.0.
      final legacy = prefs!.getString(_legacyPinKey);
      unlocked =
          legacy != null &&
          crypto.sha256.convert(utf8.encode(pin)).toString() == legacy;
      if (unlocked) {
        await _savePin(pin);
        await prefs!.remove(_legacyPinKey);
      }
    }
    if (unlocked) {
      await _resetFailures();
    } else {
      await _recordFailure();
    }
    return unlocked;
  }

  String _canonicalDeviceId(String value) => value
      .trim()
      .toUpperCase()
      .replaceFirst(RegExp(r'^V\d+-'), '')
      .replaceAll(RegExp(r'\s+'), '');

  bool _samePhysicalDevice(String first, String second) =>
      _canonicalDeviceId(first) == _canonicalDeviceId(second);

  Future<String> issue(
    String product,
    String device,
    LicensePlan plan, {
    required String customerId,
    int? customDays,
    bool flushSync = true,
    bool forceNew = false,
    DateTime? extendFromExpiry,
  }) async {
    if (!unlocked || privateKey.isEmpty || publicKey.isEmpty) {
      throw StateError('Inicia sesión para generar licencias.');
    }
    _requirePermission('gestion', 'create', 'No tienes permiso para crear licencias.');
    final normalizedDevice = device.trim();
    if (normalizedDevice.length < 8 || normalizedDevice.length > 256) {
      throw ArgumentError('El ID de dispositivo no es valido.');
    }
    final customer = customers.cast<CustomerRecord?>().firstWhere(
      (item) => item!.id == customerId,
      orElse: () => null,
    );
    if (customer == null) {
      throw StateError('El cliente seleccionado ya no existe.');
    }
    if (!_samePhysicalDevice(customer.device, normalizedDevice)) {
      throw StateError(
        'El dispositivo no coincide con el cliente seleccionado.',
      );
    }
    const productCodes = {
      'bdj_studio_sample_pad': 1,
      'bdj_studio_synth_pro': 2,
      'bdj_studio_stems_music': 3,
      'bdj_studio_wave_video': 4,
      'bdj_studio_voice_spot': 5,
      'bdj_studio_search_pro': 6,
      'bdj_studio_audio_analyzer': 7,
    };
    final productCode = productCodes[product];
    if (productCode == null) {
      throw ArgumentError('Producto no soportado.');
    }
    if (!RegExp(
          r'^[A-Z0-9]{4}(?:-[A-Z0-9]{4}){3}$',
        ).hasMatch(normalizedDevice) &&
        !RegExp(r'^V[1-9]\d*-[A-Z0-9-]+$').hasMatch(normalizedDevice)) {
      throw ArgumentError(
        'El ID de activación debe provenir de la versión actual de la aplicación.',
      );
    }

    // Evita crear códigos diferentes para un ID existente que ya tiene licencia válida en ese producto y plan
    if (!forceNew) {
      final existing = records.cast<LicenseRecord?>().firstWhere(
        (r) =>
            r != null &&
            r.isActive &&
            (r.customerId == customerId ||
                _samePhysicalDevice(r.device, normalizedDevice)) &&
            r.product == product &&
            r.plan == plan.name &&
            (plan != LicensePlan.custom ||
                r.expiresAt == null ||
                r.expiresAt!.isAfter(DateTime.now().toUtc())),
        orElse: () => null,
      );
      if (existing != null) {
        return generateSpp3TokenForRecord(existing);
      }
    }

    // Duracion efectiva: "custom" usa los dias indicados a mano; "permanent"
    // no expira (null); el resto usa los dias fijos del plan.
    final int? effectiveDays;
    if (plan == LicensePlan.custom) {
      if (customDays == null || customDays <= 0) {
        throw ArgumentError(
          'Indica una duracion personalizada valida (mayor a 0 dias).',
        );
      }
      if (customDays > 36500) {
        throw ArgumentError('La duracion personalizada es demasiado larga.');
      }
      effectiveDays = customDays;
    } else {
      effectiveDays = plan.days;
    }
    final now = DateTime.now().toUtc();
    // La renovación parte de la fecha de vencimiento vigente (si aún no
    // expiró) para sumarle los días nuevos, en lugar de reiniciar el conteo.
    final extensionBase =
        extendFromExpiry != null && extendFromExpiry.isAfter(now)
        ? extendFromExpiry
        : now;
    final expiresAt = effectiveDays == null
        ? null
        : extensionBase.add(Duration(days: effectiveDays));

    final newId = _randomId();
    final tempRecord = LicenseRecord(
      id: newId,
      product: product,
      device: normalizedDevice,
      plan: plan.name,
      issuedAt: now,
      customerId: customerId,
      customerName: customer.name,
      status: 'active',
      expiresAt: expiresAt,
      issuedBy: currentUser ?? 'desconocido',
      exactVersion: switch (product) {
        'bdj_studio_sample_pad' => '1.0.3',
        'bdj_studio_synth_pro' => '1.0.0',
        'bdj_studio_wave_video' => '1.0.0',
        'bdj_studio_stems_music' => '1.0.0',
        'bdj_studio_voice_spot' => '1.0.0',
        'bdj_studio_search_pro' => '1.0.0',
        'bdj_studio_audio_analyzer' => '1.0.0',
        _ => '1.0.0',
      },
    );
    final token = await generateSpp3TokenForRecord(tempRecord);
    final newRecord = tempRecord.copyWith(token: token);

    // Reemplazar una licencia vigente del mismo producto es una ACTUALIZACIÓN:
    // exige permiso de actualizar (el operador solo puede crear nuevas).
    final replaced = records
        .where(
          (record) =>
              record.isActive &&
              (record.customerId == customerId ||
                  _samePhysicalDevice(record.device, normalizedDevice)) &&
              record.product == product,
        )
        .toList();
    if (replaced.isNotEmpty) {
      _requirePermission(
        'gestion',
        'update',
        'Este equipo ya tiene una licencia activa de ${newRecord.productLabel}. '
            'Solo un administrador puede renovarla o cambiar su plan.',
      );
    }
    await supabase.insertLicense(newRecord);
    for (final old in replaced) {
      await supabase.patchLicense(old.id, {'status': 'replaced'});
    }
    records.removeWhere((record) => replaced.any((old) => old.id == record.id));
    records.add(newRecord.copyWith(issuedBy: currentUser));
    return token;
  }

  Future<String> generateSpp3TokenForRecord(LicenseRecord lic) async {
    if (lic.token != null &&
        lic.token!.isNotEmpty &&
        lic.token!.startsWith('SPP3.')) {
      return lic.token!;
    }
    if (_operatorKeyPair == null ||
        _adminCertificate == null ||
        _adminCertificate!.isExpired) {
      await _provisionSpp3OperatorKeys();
    }
    final hwidHash = KeyHierarchy.hashHwid(lic.device);
    final payload = Spp3Payload(
      licenseId: lic.id,
      customerId: lic.customerId ?? 'legacy_customer',
      deviceId: lic.device,
      hwidHash: hwidHash,
      productCode: lic.product,
      exactVersion: lic.exactVersion ?? lic.appVersion,
      plan: lic.plan,
      issuedAtUtc: lic.issuedAt,
      expiresAtUtc: lic.expiresAt,
    );
    final token = await Spp3Token.issue(
      payload: payload,
      signerCertificate: _adminCertificate!,
      operatorKeyPair: _operatorKeyPair!,
    );
    return token;
  }

  Future<String> replaceLicense(
    LicenseRecord current,
    LicensePlan newPlan, {
    int? customDays,
    bool flushSync = true,
  }) async {
    _requirePermission('gestion', 'update', 'No tienes permiso para renovar o editar licencias.');
    if (current.customerId == null || current.customerName == null) {
      throw StateError(
        'Esta licencia antigua no tiene un cliente asociado y no puede editarse.',
      );
    }
    // Una licencia permanente ya no se puede "extender"; se conserva la única.
    if (newPlan == LicensePlan.permanent && current.expiresAt == null) {
      return generateSpp3TokenForRecord(current);
    }
    return issue(
      current.product,
      current.device,
      newPlan,
      customerId: current.customerId!,
      customDays: customDays,
      flushSync: flushSync,
      forceNew: true,
      extendFromExpiry: current.expiresAt,
    );
  }

  // ignore: unused_element
  Future<void> _restoreProductionIssuer(String value, String pin) async {
    if (isConfigured) throw StateError('La aplicación ya está configurada.');
    if (pin.length < 8) {
      throw ArgumentError('El PIN debe tener al menos 8 caracteres.');
    }
    final parts = value.split('.');
    if (parts.length != 5 || parts.first != 'BDJB1') {
      throw const FormatException('Configuración interna inválida.');
    }
    final algorithm = AesGcm.with256bits();
    final plaintext = await algorithm.decrypt(
      SecretBox(
        base64Url.decode(parts[3]),
        nonce: base64Url.decode(parts[2]),
        mac: Mac(base64Url.decode(parts[4])),
      ),
      secretKey: SecretKey(await _derivePin(pin, base64Url.decode(parts[1]))),
    );
    final restored = jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
    final restoredPrivate = restored['privateKey'] as String;
    final restoredPublic = restored['publicKey'] as String;
    if (base64Url.decode(restoredPrivate).length != 32 ||
        base64Url.decode(restoredPublic).length != 32) {
      throw const FormatException(
        'La configuración interna no contiene claves válidas.',
      );
    }
    privateKey = restoredPrivate;
    publicKey = restoredPublic;
    await storage.write(key: 'bdj_ed25519_private', value: privateKey);
    await storage.write(key: 'bdj_ed25519_public', value: publicKey);
    await _savePin(pin);
    await _resetFailures();
    unlocked = true;
  }

  Future<void> _savePin(String pin) async {
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final hash = await _derivePin(pin, salt);
    await prefs!.setString(_pinSaltKey, base64UrlEncode(salt));
    await prefs!.setString(_pinHashKey, base64UrlEncode(hash));
  }

  // ignore: unused_element
  Future<void> _clearIssuerConfiguration() async {
    await storage.delete(key: 'bdj_ed25519_private');
    await storage.delete(key: 'bdj_ed25519_public');
    await prefs!.remove(_pinHashKey);
    await prefs!.remove(_pinSaltKey);
    await prefs!.remove(_legacyPinKey);
    privateKey = '';
    publicKey = '';
    unlocked = false;
  }

  Future<List<int>> _derivePin(String pin, List<int> salt) async {
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdf2Iterations,
      bits: 256,
    );
    final key = await algorithm.deriveKeyFromPassword(
      password: pin,
      nonce: salt,
    );
    return key.extractBytes();
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }

  Future<void> _recordFailure() async {
    final attempts = (prefs!.getInt(_failedAttemptsKey) ?? 0) + 1;
    if (attempts >= _maxAttempts) {
      await prefs!.setString(
        _lockedUntilKey,
        DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 15))
            .toIso8601String(),
      );
      await prefs!.setInt(_failedAttemptsKey, 0);
    } else {
      await prefs!.setInt(_failedAttemptsKey, attempts);
    }
  }

  Future<void> _resetFailures() async {
    await prefs!.remove(_failedAttemptsKey);
    await prefs!.remove(_lockedUntilKey);
  }

  String _randomId() {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(16, (_) => random.nextInt(256)));
  }
}

class LicenseRecord {
  const LicenseRecord({
    required this.id,
    required this.product,
    required this.device,
    required this.plan,
    required this.issuedAt,
    this.customerId,
    this.customerName,
    this.token,
    this.status = 'active',
    this.replacesLicenseId,
    this.supersededById,
    this.expiresAt,
    this.exactVersion,
    this.hwidSchemaVersion = 'V2',
    this.issuedBy,
  });

  final String id;
  final String product;
  final String device;
  final String plan;
  final DateTime issuedAt;
  final String? customerId;
  final String? customerName;
  final String? token;
  final String status;
  final String? replacesLicenseId;
  final String? supersededById;
  final DateTime? expiresAt;
  final String? exactVersion;
  final String hwidSchemaVersion;
  final String? issuedBy;

  bool get isLegacyTestLicense => hwidSchemaVersion != 'V2';

  bool get isActive =>
      status == 'active' &&
      (expiresAt == null || expiresAt!.isAfter(DateTime.now().toUtc()));

  String get productLabel => switch (product) {
    'bdj_studio_sample_pad' => 'BDJ Studio Sample Pad',
    'bdj_studio_synth_pro' => 'BDJ Studio Synth Pro',
    'bdj_studio_stems_music' => 'BDJ Studio Stems Music',
    'bdj_studio_wave_video' => 'BDJ Studio Wave Video',
    'bdj_studio_voice_spot' => 'BDJ Studio Voice Spot',
    'bdj_studio_search_pro' => 'BDJ Studio Search Pro',
    'bdj_studio_audio_analyzer' => 'BDJ Studio Audio Analyzer',
    _ => product,
  };

  String get appVersion => switch (product) {
    'bdj_studio_sample_pad' => '1.0.3',
    'bdj_studio_synth_pro' => '1.0.0',
    'bdj_studio_wave_video' => '1.0.0',
    'bdj_studio_stems_music' => '1.0.0',
    'bdj_studio_voice_spot' => '1.0.0',
    'bdj_studio_search_pro' => '1.0.0',
    'bdj_studio_audio_analyzer' => '1.0.0',
    _ => '1.0.0',
  };

  String get planLabel {
    for (final item in LicensePlan.values) {
      if (item.name == plan) return item.label;
    }
    return plan;
  }

  int? get appMajorVersion {
    final match = RegExp(r'^V(\d+)-').firstMatch(device);
    return match == null ? 1 : int.tryParse(match.group(1)!);
  }

  factory LicenseRecord.fromJson(Map<String, dynamic> json) => LicenseRecord(
    id: json['id'] as String,
    product: json['product'] as String,
    device: json['device'] as String,
    plan: json['plan'] as String,
    issuedAt: DateTime.parse(json['issuedAt'] as String),
    customerId: json['customerId'] as String?,
    customerName: json['customerName'] as String?,
    token: json['token'] as String?,
    status: json['status'] as String? ?? 'active',
    replacesLicenseId: json['replacesLicenseId'] as String?,
    supersededById: json['supersededById'] as String?,
    expiresAt: json['expiresAt'] == null
        ? null
        : DateTime.parse(json['expiresAt'] as String),
    exactVersion: json['exactVersion'] as String?,
    hwidSchemaVersion: json['hwidSchemaVersion'] as String? ?? 'V1',
    issuedBy: json['issuedBy'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'product': product,
    'device': device,
    'plan': plan,
    'issuedAt': issuedAt.toIso8601String(),
    'customerId': customerId,
    'customerName': customerName,
    'token': token,
    'status': status,
    'replacesLicenseId': replacesLicenseId,
    'supersededById': supersededById,
    'expiresAt': expiresAt?.toIso8601String(),
    'exactVersion': exactVersion ?? appVersion,
    'hwidSchemaVersion': hwidSchemaVersion,
    'issuedBy': issuedBy,
  };

  LicenseRecord copyWith({
    String? status,
    String? supersededById,
    String? customerName,
    String? token,
    String? exactVersion,
    String? hwidSchemaVersion,
    String? issuedBy,
  }) => LicenseRecord(
    id: id,
    product: product,
    device: device,
    plan: plan,
    issuedAt: issuedAt,
    customerId: customerId,
    customerName: customerName ?? this.customerName,
    token: token ?? this.token,
    status: status ?? this.status,
    replacesLicenseId: replacesLicenseId,
    supersededById: supersededById ?? this.supersededById,
    expiresAt: expiresAt,
    exactVersion: exactVersion ?? this.exactVersion,
    hwidSchemaVersion: hwidSchemaVersion ?? this.hwidSchemaVersion,
    issuedBy: issuedBy ?? this.issuedBy,
  );
}

class CustomerRecord {
  const CustomerRecord({
    required this.id,
    required this.name,
    required this.email,
    required this.device,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final String device;
  final DateTime createdAt;

  factory CustomerRecord.fromJson(Map<String, dynamic> json) => CustomerRecord(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    device: json['device'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'device': device,
    'createdAt': createdAt.toIso8601String(),
  };
}

class AdminAccount {
  const AdminAccount({
    this.id,
    required this.email,
    this.passwordHash = '',
    this.passwordSalt,
    required this.role,
    this.isActive = true,
    this.permissions,
    this.userId,
  });

  final String? id;
  final String email;
  /// Obsoleto: las contraseñas viven en Supabase Auth. Se conserva solo para
  /// compatibilidad con el flujo de bootstrap heredado.
  final String passwordHash;
  final String? passwordSalt;
  /// Id del rol en la tabla `roles` (super_admin, license_admin, operator,
  /// auditor, custom o un rol personalizado).
  final String role;
  final bool isActive;
  /// Solo se usa cuando role == 'custom'.
  final Map<String, Map<String, bool>>? permissions;
  final String? userId;

  /// Módulos disponibles en el sistema.
  static const availableModules = ['gestion', 'usuarios'];

  /// Acciones CRUD disponibles.
  static const availableActions = ['create', 'read', 'update', 'delete'];

  /// Unifica alias antiguos ('super', 'Super Admin') con los ids de la BD.
  static String normalizeRole(String? raw) {
    final r = (raw ?? '').trim();
    if (r == 'super' || r == 'super_admin' || r == 'Super Admin') return 'super_admin';
    if (r.isEmpty) return 'operator';
    return r;
  }

  static Map<String, Map<String, bool>> _copy(Map<String, Map<String, bool>> src) =>
      src.map((k, v) => MapEntry(k, Map<String, bool>.from(v)));

  /// Permisos por defecto: acceso total a todo (Super Admin).
  static Map<String, Map<String, bool>> defaultPermissions() =>
      _copy(AppRole.superAdmin.permissions);

  /// Permisos para Operador de Licencias.
  static Map<String, Map<String, bool>> operatorPermissions() =>
      _copy(AppRole.operator.permissions);

  /// Permisos para Auditor.
  static Map<String, Map<String, bool>> auditorPermissions() =>
      _copy(AppRole.auditor.permissions);

  bool get isSuperAdmin => role == 'super_admin';

  /// Etiqueta legible del rol.
  String get displayRole {
    switch (role) {
      case 'super_admin':
        return 'Super Administrador';
      case 'license_admin':
        return 'Administrador de Licencias';
      case 'operator':
        return 'Operador de Licencias';
      case 'auditor':
        return 'Auditor';
      default:
        return 'Personalizado';
    }
  }

  /// Aproximación local (solo UI) usando los roles de sistema. La consola usa
  /// LicenseIssuer.canDo, que toma los roles reales cargados desde la BD.
  bool hasPermission(String module, String action) {
    if (role == 'super_admin') return true;
    final m = (module == 'admins') ? 'usuarios' : module;
    if (role == 'custom') {
      return permissions?[m]?[action] ?? false;
    }
    for (final r in AppRole.systemRoles) {
      if (r.id == role) return r.hasPermission(m, action);
    }
    return false;
  }

  static Map<String, Map<String, bool>>? _parsePermissions(Object? raw) {
    if (raw is! Map) return null;
    final perms = <String, Map<String, bool>>{};
    for (final entry in raw.entries) {
      if (entry.value is Map) {
        perms[entry.key.toString()] = {
          for (final e in (entry.value as Map).entries)
            e.key.toString(): e.value == true,
        };
      }
    }
    return perms;
  }

  factory AdminAccount.fromJson(Map<String, dynamic> json) => AdminAccount(
        id: json['id'] as String?,
        email: (json['email'] as String).trim().toLowerCase(),
        passwordHash: json['passwordHash'] as String? ?? '',
        passwordSalt: json['passwordSalt'] as String?,
        role: normalizeRole(json['role'] as String?),
        isActive: json['isActive'] as bool? ?? true,
        permissions: _parsePermissions(json['permissions']),
      );

  /// Fila de la tabla admin_accounts de Supabase.
  factory AdminAccount.fromRemote(Map<dynamic, dynamic> json) => AdminAccount(
        id: json['id'] as String?,
        email: (json['email'] as String).trim().toLowerCase(),
        role: normalizeRole(json['role'] as String?),
        isActive: json['is_active'] as bool? ?? true,
        permissions: _parsePermissions(json['permissions']),
        userId: json['user_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'role': role,
        'isActive': isActive,
        'permissions': permissions,
      };
}
