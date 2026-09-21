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
  final deviceId = TextEditingController();
  final customerName = TextEditingController();
  final customerEmail = TextEditingController();
  final adminEmail = TextEditingController();
  final adminPassword = TextEditingController();
  final blockReason = TextEditingController();
  final customerSearch = TextEditingController();
  var selectedProducts = <String>{'bdj_studio_sample_pad'};
  var plan = LicensePlan.permanent;
  var customYears = 0;
  var customMonths = 0;
  var customDaysInput = 0;
  var obscurePassword = true;
  var obscureAdminPassword = true;
  var selectedSection = 0;
  var customerPage = 0;
  String? error;
  bool isProcessing = false;
  String processingMessage = '';
  Timer? _liveSyncTimer;

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
    deviceId.dispose();
    customerName.dispose();
    customerEmail.dispose();
    adminEmail.dispose();
    adminPassword.dispose();
    blockReason.dispose();
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

  Future<void> addCustomer() async {
    if (isProcessing) return;
    setState(() {
      isProcessing = true;
      processingMessage = 'Guardando datos del cliente...';
    });
    try {
      await widget.issuer.addCustomer(
        customerName.text.trim(),
        customerEmail.text.trim(),
        deviceId.text.trim(),
      );
      customerName.clear();
      customerEmail.clear();
      setState(() {
        deviceId.clear();
        error = null;
      });
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
      processingMessage = 'Creando Super Admin...';
    });
    try {
      await widget.issuer.addAdmin(adminEmail.text.trim(), adminPassword.text);
      adminEmail.clear();
      adminPassword.clear();
      setState(() => error = null);
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
  static const _blockedDevicesKey = 'issuer_blocked_devices_v1';
  static const _syncQueueKey = 'issuer_sync_queue_v1';
  static const _currentSessionEmailKey = 'issuer_session_email_v1';
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
  final List<LicenseRecord> records = [];
  final List<CustomerRecord> customers = [];
  final List<AdminAccount> admins = [];
  final List<BlockedDeviceRecord> blockedDevices = [];
  final supabase = SupabaseService();
  bool isSyncing = false;
  bool _flushingSyncQueue = false;
  bool get isConfigured => privateKey.isNotEmpty && publicKey.isNotEmpty;

  // Credenciales temporales de pruebas. Solo se almacena un verificador PBKDF2
  // (nunca la contraseña); reemplázalas desde Usuarios antes de distribuir.
  static const _testAdmins = [
    (
      email: 'david.zapata@bdjstudio.com',
      salt: 'EhqWvzAIL8vkDSvaChTQzg==',
      hash: '9ka0UENRF-O4g34-yH5bwaH8qGJsM96wmAXevzutdrg=',
    ),
    (
      email: 'maylor.neyra@bdjstudio.com',
      salt: 'K3vq2zuglUt9CQutuVL0ng==',
      hash: 'D7s12WH1yJkGDYAQatS2LrRa8fIgRfaWv6CdhNrFHKU=',
    ),
  ];

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
    final storedRecords = prefs!.getStringList(_recordsKey) ?? const [];
    records.clear();
    for (final value in storedRecords) {
      try {
        records.add(
          LicenseRecord.fromJson(jsonDecode(value) as Map<String, dynamic>),
        );
      } on FormatException {
        // Ignore a damaged audit entry without blocking access to the issuer.
      } on TypeError {
        // Ignore legacy entries with an incompatible schema.
      }
    }
    final recordsWereConsolidated = _consolidateLicenseRecords();
    if (recordsWereConsolidated) {
      await _saveLicenseRecords();
    }
    customers.clear();
    for (final value
        in prefs!.getStringList(_customersKey) ?? const <String>[]) {
      try {
        customers.add(
          CustomerRecord.fromJson(jsonDecode(value) as Map<String, dynamic>),
        );
      } on FormatException {
        // A damaged local row must not prevent the console from starting.
      } on TypeError {
        // Ignore rows written with an incompatible legacy schema.
      }
    }
    admins.clear();
    for (final value in prefs!.getStringList(_adminsKey) ?? const <String>[]) {
      try {
        admins.add(
          AdminAccount.fromJson(jsonDecode(value) as Map<String, dynamic>),
        );
      } catch (_) {}
    }
    await _restoreTestAdminIfMissing();

    blockedDevices.clear();
    for (final value
        in prefs!.getStringList(_blockedDevicesKey) ?? const <String>[]) {
      try {
        blockedDevices.add(
          BlockedDeviceRecord.fromJson(
            jsonDecode(value) as Map<String, dynamic>,
          ),
        );
      } on FormatException {
        // A damaged local row must not prevent the console from starting.
      } on TypeError {
        // Ignore rows written with an incompatible legacy schema.
      }
    }

    final savedSession = prefs!.getString(_currentSessionEmailKey);
    if (savedSession != null && savedSession.isNotEmpty) {
      for (final a in admins) {
        if (a.email.toLowerCase() == savedSession.toLowerCase() && a.isActive) {
          unlocked = true;
          currentUser = a.email;
          currentRole = a.role;
          break;
        }
      }
    }
    unawaited(syncWithCloud().then((_) {
      if (!unlocked && savedSession != null && savedSession.isNotEmpty) {
        for (final a in admins) {
          if (a.email.toLowerCase() == savedSession.toLowerCase() && a.isActive) {
            unlocked = true;
            currentUser = a.email;
            currentRole = a.role;
            break;
          }
        }
      }
    }));
  }

  Future<void> syncWithCloud() async {
    if (isSyncing) return;
    isSyncing = true;
    try {
      final results = await Future.wait([
        supabase.fetchCustomers(),
        supabase.fetchLicenses(),
        supabase.fetchBlockedDevices(),
        supabase.fetchAdmins(),
      ]);
      final cloudCustomers = results[0] as List<CustomerRecord>?;
      final cloudLicenses = results[1] as List<LicenseRecord>?;
      final cloudBlocks = results[2] as List<BlockedDeviceRecord>?;
      final cloudAdmins = results[3] as List<AdminAccount>?;

      // Supabase es la ÚNICA FUENTE DE VERDAD.
      // Si la consulta fue exitosa (no es null), el estado local se reemplaza
      // fielmente por lo que está en la nube.
      // NUNCA resubimos 'localOnly', pues son registros que fueron eliminados por otro administrador.
      if (cloudCustomers != null) {
        customers
          ..clear()
          ..addAll(cloudCustomers);
        await prefs?.setStringList(
          _customersKey,
          customers.map((item) => jsonEncode(item.toJson())).toList(),
        );
      }

      if (cloudLicenses != null) {
        records
          ..clear()
          ..addAll(cloudLicenses);
        await _saveLicenseRecords();
      }

      if (cloudBlocks != null) {
        blockedDevices
          ..clear()
          ..addAll(cloudBlocks);
        await _saveBlockedDevices();
      }

      if (cloudAdmins != null && cloudAdmins.isNotEmpty) {
        admins
          ..clear()
          ..addAll(cloudAdmins);
        await _saveAdmins();
      }
    } catch (e) {
      debugPrint('Error en syncWithCloud: $e');
    } finally {
      isSyncing = false;
    }
  }

  /// Hace recuperable una instalación limpia y agrega las cuentas temporales
  /// faltantes en instalaciones de prueba existentes.
  Future<void> _restoreTestAdminIfMissing() async {
    if (prefs!.getBool(_testAdminsMigrationKey) == true) return;
    var changed = false;
    for (final testAdmin in _testAdmins) {
      final index = admins.indexWhere(
        (admin) => admin.email.toLowerCase() == testAdmin.email,
      );
      final previous = index >= 0 ? admins[index] : null;
      final repaired = AdminAccount(
        id: previous?.id,
        email: testAdmin.email,
        passwordHash: testAdmin.hash,
        passwordSalt: testAdmin.salt,
        role: 'super',
        isActive: true,
      );
      if (index >= 0) {
        admins[index] = repaired;
      } else {
        admins.add(repaired);
      }
      changed = true;
    }
    if (changed) await _saveAdmins();
    await prefs!.setBool(_testAdminsMigrationKey, true);
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
        role: 'super',
      ),
    );
    await prefs!.setStringList(
      _adminsKey,
      admins.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  Future<void> _ensureCurrentUserInAdmins([String? password]) async {
    if (currentUser != null && currentUser!.isNotEmpty) {
      final normalized = currentUser!.toLowerCase();
      final existingIndex = admins.indexWhere(
        (a) => a.email.toLowerCase() == normalized,
      );

      String hashStr = '';
      String saltStr = '';
      if (password != null && password.isNotEmpty) {
        final saltBytes = List<int>.generate(
          16,
          (_) => Random.secure().nextInt(256),
        );
        final derivedHash = await _derivePin(password, saltBytes);
        saltStr = base64UrlEncode(saltBytes);
        hashStr = base64UrlEncode(derivedHash);
      }

      if (existingIndex == -1) {
        admins.add(
          AdminAccount(
            email: currentUser!,
            passwordHash: hashStr,
            passwordSalt: saltStr,
            role: 'super',
            isActive: true,
          ),
        );
        await _saveAdmins();
      } else if (password != null && password.isNotEmpty) {
        admins[existingIndex] = AdminAccount(
          id: admins[existingIndex].id,
          email: admins[existingIndex].email,
          passwordHash: hashStr,
          passwordSalt: saltStr,
          role: admins[existingIndex].role,
          isActive: admins[existingIndex].isActive,
        );
        await _saveAdmins();
      }
    }
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

  Future<bool> _verifyOfflinePassword(String email, String password) async {
    final normalized = email.trim().toLowerCase();
    final cleanPassword = password.trim();

    if (!normalized.contains('@') || cleanPassword.isEmpty) return false;

    AdminAccount? targetAdmin;
    for (final a in admins) {
      if (a.email.toLowerCase() == normalized) {
        targetAdmin = a;
        break;
      }
    }

    if (targetAdmin != null &&
        targetAdmin.passwordHash.isNotEmpty &&
        (targetAdmin.passwordSalt ?? '').isNotEmpty) {
      try {
        final saltBytes = base64Url.decode(targetAdmin.passwordSalt!);
        final expectedHash = base64Url.decode(targetAdmin.passwordHash);
        final derivedHash = await _derivePin(password, saltBytes);
        if (_constantTimeEquals(expectedHash, derivedHash)) return true;
        final derivedHashTrim = await _derivePin(cleanPassword, saltBytes);
        return _constantTimeEquals(expectedHash, derivedHashTrim);
      } catch (_) {
        return false;
      }
    }

    // Estrictamente fail-closed. No existen contraseñas de prueba ni accesos por longitud.
    return false;
  }

  Future<bool> login(String email, String password) async {
    final normalizedEmail = email.trim().toLowerCase();
    final cleanPassword = password.trim();
    if (!normalizedEmail.contains('@') || cleanPassword.isEmpty) {
      return false;
    }

    // La consola emisora es estrictamente offline: no depende de servidor,
    // conectividad, ni tokens remotos para autenticar al operador.
    var isValid = await _verifyOfflinePassword(normalizedEmail, password);
    if (!isValid) {
      try {
        await syncWithCloud();
        isValid = await _verifyOfflinePassword(normalizedEmail, password);
      } catch (_) {}
    }
    if (isValid) {
      unlocked = true;
      await _resetFailures();
      currentUser = normalizedEmail;
      currentRole = 'super';
      await _ensureCurrentUserInAdmins(cleanPassword);
      await prefs!.setString(_currentSessionEmailKey, normalizedEmail);
      return true;
    }

    return false;
  }

  Future<void> _saveAdmins() async {
    await prefs!.setStringList(
      _adminsKey,
      admins.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  /// Crea el superadministrador de una instalación sin usuarios. Nunca guarda
  /// la contraseña en claro y deja de estar disponible al registrar la primera
  /// cuenta local.
  Future<void> initializeInitialOwner({
    required String email,
    required String password,
  }) async {
    if (admins.isNotEmpty) {
      throw StateError('La cuenta inicial ya fue configurada.');
    }
    final normalizedEmail = email.trim().toLowerCase();
    final cleanPassword = password.trim();
    if (!normalizedEmail.contains('@') || cleanPassword.length < 12) {
      throw ArgumentError(
        'Indica un correo válido y una contraseña de al menos 12 caracteres.',
      );
    }

    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final hash = await _derivePin(cleanPassword, salt);
    admins.add(
      AdminAccount(
        email: normalizedEmail,
        passwordHash: base64UrlEncode(hash),
        passwordSalt: base64UrlEncode(salt),
        role: 'super',
        isActive: true,
      ),
    );
    await _saveAdmins();
    await _resetFailures();
    unlocked = true;
    currentUser = normalizedEmail;
    currentRole = 'super';
  }

  Future<void> refreshAdmins() async {
    final payload = await _apiRequest('GET', '/admin/admins');
    if (payload is! List) {
      throw StateError('Respuesta de administradores invalida.');
    }
    admins
      ..clear()
      ..addAll(payload.whereType<Map>().map(AdminAccount.fromRemote));
    await _saveAdmins();
  }

  Future<void> addAdmin(String email, String password) async {
    final normalized = email.trim().toLowerCase();
    final saltBytes = List<int>.generate(
      16,
      (_) => Random.secure().nextInt(256),
    );
    final derivedHash = await _derivePin(password, saltBytes);
    final saltStr = base64UrlEncode(saltBytes);
    final hashStr = base64UrlEncode(derivedHash);

    try {
      await _apiRequest(
        'POST',
        '/admin/admins',
        body: {
          'email': normalized,
          'password': password,
          'name': normalized.split('@').first,
        },
      );
      await refreshAdmins();
    } catch (_) {}
    final account = AdminAccount(
      id: 'admin_${DateTime.now().millisecondsSinceEpoch}',
      email: normalized,
      passwordHash: hashStr,
      passwordSalt: saltStr,
      role: 'super',
      isActive: true,
    );
    final existingIdx = admins.indexWhere((a) => a.email.toLowerCase() == normalized);
    if (existingIdx >= 0) {
      admins[existingIdx] = account;
    } else {
      admins.add(account);
    }
    await _saveAdmins();
    await supabase.syncAdmin(account);
  }

  Future<void> deleteAdmin(String id) async {
    final normalized = id.trim().toLowerCase();
    if (normalized == 'david.zapata@bdjstudio.com' ||
        admins.any((a) =>
            (a.id?.toLowerCase() == normalized ||
                a.email.toLowerCase() == normalized) &&
            a.email.toLowerCase() == 'david.zapata@bdjstudio.com')) {
      throw StateError(
        'La cuenta de david.zapata@bdjstudio.com es el creador y Super Admin principal. No puede ser eliminada.',
      );
    }
    final target = admins.cast<AdminAccount?>().firstWhere(
      (a) => a?.id == id || a?.email.toLowerCase() == normalized,
      orElse: () => null,
    );
    admins.removeWhere((a) => a.id == id || a.email.toLowerCase() == normalized);
    await _saveAdmins();
    if (target != null) {
      await supabase.deleteAdmin(target.email);
    } else {
      await supabase.deleteAdmin(normalized);
    }
  }

  Future<void> updateAdmin(
    String id, {
    required String email,
    String? password,
  }) async {
    final normalized = email.trim().toLowerCase();
    final index = admins.indexWhere(
      (admin) => admin.id == id || admin.email.toLowerCase() == id.toLowerCase(),
    );
    if (index >= 0) {
      final previous = admins[index];
      String hash = previous.passwordHash;
      String salt = previous.passwordSalt ?? '';
      if (password != null && password.isNotEmpty) {
        final saltBytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
        final derived = await _derivePin(password, saltBytes);
        salt = base64UrlEncode(saltBytes);
        hash = base64UrlEncode(derived);
      }
      final updated = AdminAccount(
        id: previous.id ?? 'admin_${DateTime.now().millisecondsSinceEpoch}',
        email: normalized,
        passwordHash: hash,
        passwordSalt: salt,
        role: previous.role,
        isActive: previous.isActive,
      );
      admins[index] = updated;
      await _saveAdmins();
      await supabase.syncAdmin(updated);
    }
  }

  Future<bool> changeAdminPassword(
    String email,
    String currentPassword,
    String newPassword,
  ) async {
    final normalized = email.trim().toLowerCase();
    if (newPassword.trim().length < 6) {
      throw ArgumentError(
        'La nueva contraseña debe tener al menos 6 caracteres.',
      );
    }

    final isValidCurrent = await _verifyOfflinePassword(
      normalized,
      currentPassword,
    );
    if (!isValidCurrent) {
      return false;
    }

    final saltBytes = List<int>.generate(
      16,
      (_) => Random.secure().nextInt(256),
    );
    final derivedHash = await _derivePin(newPassword.trim(), saltBytes);
    final saltStr = base64UrlEncode(saltBytes);
    final hashStr = base64UrlEncode(derivedHash);

    try {
      await _apiRequest(
        'POST',
        '/admin/auth/change-password',
        body: {
          'email': normalized,
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        },
      );
    } catch (_) {}

    final index = admins.indexWhere((a) => a.email.toLowerCase() == normalized);
    if (index != -1) {
      admins[index] = AdminAccount(
        id: admins[index].id,
        email: admins[index].email,
        passwordHash: hashStr,
        passwordSalt: saltStr,
        role: admins[index].role,
        isActive: admins[index].isActive,
      );
    } else {
      admins.add(
        AdminAccount(
          email: normalized,
          passwordHash: hashStr,
          passwordSalt: saltStr,
          role: 'super',
          isActive: true,
        ),
      );
    }
    await _saveAdmins();
    final updatedAdmin = admins.firstWhere((a) => a.email.toLowerCase() == normalized);
    try {
      await supabase.syncAdmin(updatedAdmin);
    } catch (_) {}
    return true;
  }

  Future<Object?> _apiRequest(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    throw UnsupportedError(
      'BDJ Studio License funciona exclusivamente offline.',
    );
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
          role: 'super',
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

  void logout() {
    unlocked = false;
    currentUser = null;
    currentRole = null;
    prefs?.remove(_currentSessionEmailKey);
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
    // local representa un equipo concreto, por lo que el correo NO identifica
    // por sí solo al registro: solo el ID físico evita duplicados.
    final existingIndex = customers.indexWhere(
      (c) => _samePhysicalDevice(c.device, normalizedDevice),
    );

    if (existingIndex >= 0) {
      final existing = customers[existingIndex];
      // Si el equipo ya está registrado, no se emiten cuentas ni licencias
      // duplicadas. Un correo repetido con OTRO ID crea un segundo dispositivo.
      final isLegacyDeviceId = RegExp(
        r'^V[1-9]\d*-[A-Z0-9-]+$',
      ).hasMatch(existing.device.toUpperCase());
      if ((_samePhysicalDevice(existing.device, normalizedDevice) ||
              isLegacyDeviceId) &&
          existing.device != normalizedDevice) {
        final migrated = CustomerRecord(
          id: existing.id,
          name: existing.name,
          email: existing.email,
          device: normalizedDevice,
          createdAt: existing.createdAt,
        );
        customers[existingIndex] = migrated;
        await prefs!.setStringList(
          _customersKey,
          customers.map((item) => jsonEncode(item.toJson())).toList(),
        );
        try {
          await supabase.syncCustomer(migrated);
        } catch (_) {}
        await _enqueueSync('/issuer/customers/sync', {
          'externalId': migrated.id,
          'name': migrated.name,
          'email': migrated.email,
          'deviceId': migrated.device,
        }, flushNow: flushSync);
        return migrated;
      }
      return existing;
    }

    // 2. Si es un cliente nuevo, si no se especifican nombre o correo se asignan por defecto según el ID del dispositivo
    final resolvedName = normalizedName.isNotEmpty
        ? normalizedName
        : 'Dispositivo ${_shortDeviceId(normalizedDevice)}';
    final resolvedEmail =
        (normalizedEmail.isNotEmpty && normalizedEmail.contains('@'))
        ? normalizedEmail
        : 'device_${normalizedDevice.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase()}@bdjstudio.local';

    var newCustomer = CustomerRecord(
      id: _randomId(),
      name: resolvedName,
      email: resolvedEmail,
      device: normalizedDevice,
      createdAt: DateTime.now().toUtc(),
    );
    customers.add(newCustomer);
    await prefs!.setStringList(
      _customersKey,
      customers.map((item) => jsonEncode(item.toJson())).toList(),
    );
    try {
      await supabase.syncCustomer(newCustomer);
    } catch (_) {}
    await _enqueueSync('/issuer/customers/sync', {
      'externalId': newCustomer.id,
      'name': newCustomer.name,
      'email': newCustomer.email,
      'deviceId': newCustomer.device,
    }, flushNow: flushSync);
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
    if (currentRole != 'super') {
      throw StateError('Solo un Super Admin puede eliminar clientes.');
    }

    final targetCustomer = customers.cast<CustomerRecord?>().firstWhere(
      (c) => c?.id == customerId,
      orElse: () => null,
    );
    final targetDevice = targetCustomer?.device.trim();

    // Eliminamos localmente las licencias asociadas al cliente y/o su dispositivo
    records.removeWhere((r) =>
        r.customerId == customerId ||
        (targetDevice != null &&
            targetDevice.isNotEmpty &&
            r.device.trim().toLowerCase() == targetDevice.toLowerCase()));
    await _saveLicenseRecords();

    customers.removeWhere((customer) => customer.id == customerId);
    await prefs!.setStringList(
      _customersKey,
      customers.map((item) => jsonEncode(item.toJson())).toList(),
    );
    try {
      await supabase.deleteCustomer(customerId, device: targetDevice);
    } catch (_) {}

    // En backend se borran en cascada las licencias vinculadas en una sola petición.
    await _enqueueSync(
      '/issuer/customers/${Uri.encodeComponent(customerId)}',
      const {},
      method: 'DELETE',
    );
  }

  Future<void> deleteLicense(String licenseId) async {
    if (currentRole != 'super') {
      throw StateError('Solo un Super Admin puede eliminar licencias.');
    }
    records.removeWhere((r) => r.id == licenseId);
    await _saveLicenseRecords();
    try {
      await supabase.deleteLicense(licenseId);
    } catch (_) {}
  }

  Future<void> updateCustomer(
    String customerId, {
    required String name,
    required String email,
    required String device,
  }) async {
    if (currentRole != 'super') {
      throw StateError('Solo un Super Admin puede editar clientes.');
    }
    if (name.trim().isEmpty ||
        !email.contains('@') ||
        device.trim().length < 8) {
      throw ArgumentError(
        'Nombre y correo válidos, e ID de dispositivo de al menos 8 caracteres, son obligatorios.',
      );
    }
    final index = customers.indexWhere((customer) => customer.id == customerId);
    if (index < 0) throw StateError('El cliente ya no existe.');
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedDevice = device.trim();
    final current = customers[index];
    final newName = name.trim();
    customers[index] = CustomerRecord(
      id: current.id,
      name: newName,
      email: normalizedEmail,
      device: normalizedDevice,
      createdAt: current.createdAt,
    );
    // Propagar el nuevo nombre a las licencias de este cliente: guardaban una
    // copia del nombre al emitirse, y sin esto el Dashboard/actividad seguian
    // mostrando el nombre viejo aunque el cliente ya se renombro.
    var recordsChanged = false;
    for (var i = 0; i < records.length; i++) {
      if (records[i].customerId == customerId &&
          records[i].customerName != newName) {
        records[i] = records[i].copyWith(customerName: newName);
        recordsChanged = true;
      }
    }
    await prefs!.setStringList(
      _customersKey,
      customers.map((item) => jsonEncode(item.toJson())).toList(),
    );
    if (recordsChanged) {
      await _saveLicenseRecords();
    }
    try {
      await supabase.syncCustomer(customers[index]);
    } catch (_) {}
    await _enqueueSync('/issuer/customers/sync', {
      'externalId': current.id,
      'name': newName,
      'email': normalizedEmail,
      'deviceId': normalizedDevice,
    });
  }

  /// Deja exactamente los productos seleccionados para un dispositivo. Las
  /// licencias retiradas se eliminan localmente y se propagan al servidor.
  Future<void> setProductAccess({
    required String customerId,
    required String device,
    required Set<String> products,
    bool flushSync = true,
  }) async {
    if (currentRole != 'super') {
      throw StateError('Solo un Super Admin puede gestionar accesos.');
    }
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
    records.removeWhere(
      (record) => removed.any((item) => item.id == record.id),
    );
    await _saveLicenseRecords();
    for (final rem in removed) {
      try {
        await supabase.deleteLicense(rem.id);
      } catch (_) {}
    }
    for (var index = 0; index < removed.length; index++) {
      await _enqueueSync(
        '/issuer/licenses/${Uri.encodeComponent(removed[index].id)}',
        const {},
        method: 'DELETE',
        flushNow: flushSync && index == removed.length - 1,
      );
    }
  }

  bool isDeviceBlocked(String device) => blockedDevices.any(
    (item) => item.device.toLowerCase() == device.trim().toLowerCase(),
  );

  Future<void> blockDevice(
    String device,
    String reason, {
    String? customerId,
  }) async {
    if (currentRole != 'super') {
      throw StateError('Solo un Super Admin puede bloquear dispositivos.');
    }
    final normalizedDevice = device.trim();
    if (normalizedDevice.length < 8) {
      throw ArgumentError('Ingresa un ID de dispositivo v\u00e1lido.');
    }
    if (isDeviceBlocked(normalizedDevice)) {
      throw StateError('El dispositivo ya est\u00e1 en la lista negra.');
    }
    blockedDevices.add(
      BlockedDeviceRecord(
        device: normalizedDevice,
        reason: reason.trim().isEmpty
            ? 'Bloqueado por Super Admin'
            : reason.trim(),
        customerId: customerId,
        blockedAt: DateTime.now().toUtc(),
      ),
    );
    await _saveBlockedDevices();
    try {
      await supabase.syncBlockedDevice(blockedDevices.last);
    } catch (_) {}
    await _enqueueSync('/issuer/device-blocks/sync', {
      'deviceId': normalizedDevice,
      'reason': reason.trim().isEmpty
          ? 'Bloqueado por administración'
          : reason.trim(),
      'blockedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> unblockDevice(String device) async {
    if (currentRole != 'super') {
      throw StateError('Solo un Super Admin puede desbloquear dispositivos.');
    }
    blockedDevices.removeWhere(
      (item) => item.device.toLowerCase() == device.trim().toLowerCase(),
    );
    await _saveBlockedDevices();
    try {
      await supabase.deleteBlockedDevice(device.trim());
    } catch (_) {}
    await _enqueueSync(
      '/issuer/device-blocks/${Uri.encodeComponent(device.trim())}',
      const {},
      method: 'DELETE',
    );
  }

  Future<void> _saveBlockedDevices() => prefs!.setStringList(
    _blockedDevicesKey,
    blockedDevices.map((item) => jsonEncode(item.toJson())).toList(),
  );

  // ignore: unused_element
  Future<void> _legacyAddAdminLocal(String email, String password) async {
    if (currentRole != 'super') {
      throw StateError('Solo un Super Admin puede crear usuarios.');
    }
    final normalizedEmail = email.trim().toLowerCase();
    if (!normalizedEmail.contains('@') || password.length < 8) {
      throw ArgumentError(
        'Correo valido y contrasena de 8 caracteres requeridos.',
      );
    }
    if (admins.any((admin) => admin.email == normalizedEmail)) {
      throw StateError('El usuario ya existe.');
    }
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final passwordHash = await _derivePin(password, salt);
    admins.add(
      AdminAccount(
        email: normalizedEmail,
        passwordHash: base64UrlEncode(passwordHash),
        passwordSalt: base64UrlEncode(salt),
        role: 'super',
      ),
    );
    await prefs!.setStringList(
      _adminsKey,
      admins.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  // ignore: unused_element
  Future<void> _legacyDeleteAdmin(String email) async {
    if (currentRole != 'super') {
      throw StateError('Solo un Super Admin puede eliminar usuarios.');
    }
    admins.removeWhere((admin) => admin.email == email.toLowerCase());
    await prefs!.setStringList(
      _adminsKey,
      admins.map((item) => jsonEncode(item.toJson())).toList(),
    );
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
    final normalizedDevice = device.trim();
    if (normalizedDevice.length < 8 || normalizedDevice.length > 256) {
      throw ArgumentError('El ID de dispositivo no es valido.');
    }
    if (isDeviceBlocked(normalizedDevice)) {
      throw StateError(
        'Este ID de dispositivo est\u00e1 bloqueado y no puede recibir licencias.',
      );
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

    records.removeWhere(
      (record) =>
          (record.customerId == customerId ||
              _samePhysicalDevice(record.device, normalizedDevice)) &&
          record.product == product,
    );
    records.add(newRecord);
    await _saveLicenseRecords();
    try {
      await supabase.syncLicense(newRecord);
    } catch (_) {}
    await _enqueueSync('/issuer/licenses/sync', {
      'externalId': newRecord.id,
      'customerExternalId': customer.id,
      'product': newRecord.product,
      'deviceId': newRecord.device,
      'plan': newRecord.plan,
      'tokenDigest': crypto.sha256.convert(utf8.encode(token)).toString(),
      'issuedAt': newRecord.issuedAt.toIso8601String(),
      'expiresAt': newRecord.expiresAt?.toIso8601String(),
      'status': newRecord.status,
    }, flushNow: flushSync);
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

  Future<void> _enqueueSync(
    String path,
    Map<String, Object?> body, {
    String method = 'POST',
    bool flushNow = true,
  }) async {
    // No dejamos una cola remota persistente: todos los cambios son locales.
    await prefs!.remove(_syncQueueKey);
  }

  // ignore: unused_element
  Future<void> _flushSyncQueue() async {
    if (_flushingSyncQueue) return;
    if (currentRole != 'super') return;
    _flushingSyncQueue = true;
    try {
      while (true) {
        final queued = prefs!.getStringList(_syncQueueKey) ?? <String>[];
        if (queued.isEmpty) break;
        final pending = <String>[];
        for (final entry in queued) {
          try {
            final value = jsonDecode(entry);
            if (value is! Map ||
                value['path'] is! String ||
                value['body'] is! Map) {
              continue;
            }
            await _apiRequest(
              value['method'] is String ? value['method'] as String : 'POST',
              value['path'] as String,
              body: Map<String, Object?>.from(value['body'] as Map),
            );
          } on Object {
            pending.add(entry);
          }
        }
        await prefs!.setStringList(_syncQueueKey, pending);
        final nextQueue = prefs!.getStringList(_syncQueueKey) ?? <String>[];
        if (nextQueue.length <= pending.length) break;
      }
    } finally {
      _flushingSyncQueue = false;
    }
  }

  /// La caché local tiene prioridad para no perder trabajo hecho offline. El
  /// backend no guarda el token SPP3, por lo que las licencias importadas se
  /// muestran como registro/auditoría pero nunca sustituyen una clave local.
  // ignore: unused_element
  Future<void> _mergeRemoteSnapshot() async {
    try {
      final snapshot = await _apiRequest('GET', '/issuer/snapshot');
      if (snapshot is! Map) return;
      // Tras vaciar la cola, el backend pasa a ser la fuente de verdad. Esto
      // elimina registros locales heredados que nunca se sincronizaron. Si
      // todavia hay operaciones offline pendientes, se conserva la cache para
      // no ocultar trabajo que aun no llego al servidor.
      final hasPendingSync =
          (prefs!.getStringList(_syncQueueKey) ?? const <String>[]).isNotEmpty;
      final snapshotReplacedLocal = !hasPendingSync;
      if (snapshotReplacedLocal) {
        customers.clear();
        records.clear();
        blockedDevices.clear();
      }
      var customersChanged = false;
      final remoteCustomers = snapshot['customers'];
      if (remoteCustomers is List) {
        for (final item in remoteCustomers.whereType<Map>()) {
          final externalId = item['externalId'];
          final name = item['name'];
          final email = item['email'];
          final deviceId = item['deviceId'];
          if (externalId is! String ||
              name is! String ||
              email is! String ||
              deviceId is! String ||
              customers.any((customer) => customer.id == externalId)) {
            continue;
          }
          customers.add(
            CustomerRecord(
              id: externalId,
              name: name,
              email: email,
              device: deviceId,
              createdAt:
                  DateTime.tryParse(
                    item['createdAt']?.toString() ?? '',
                  )?.toUtc() ??
                  DateTime.now().toUtc(),
            ),
          );
          customersChanged = true;
        }
      }

      var recordsChanged = false;
      final remoteLicenses = snapshot['licenses'];
      if (remoteLicenses is List) {
        for (final item in remoteLicenses.whereType<Map>()) {
          final externalId = item['externalId'];
          final product = item['product'];
          final deviceId = item['deviceId'];
          final planName = item['plan'];
          final status = item['status'];
          final customer = item['customer'];
          if (externalId is! String ||
              product is! String ||
              deviceId is! String ||
              planName is! String ||
              status is! String ||
              customer is! Map ||
              customer['externalId'] is! String ||
              records.any((record) => record.id == externalId)) {
            continue;
          }
          records.add(
            LicenseRecord(
              id: externalId,
              product: product,
              device: deviceId,
              plan: planName,
              issuedAt:
                  DateTime.tryParse(
                    item['issuedAt']?.toString() ?? '',
                  )?.toUtc() ??
                  DateTime.now().toUtc(),
              customerId: customer['externalId'] as String,
              customerName: customers
                  .cast<CustomerRecord?>()
                  .firstWhere(
                    (candidate) =>
                        candidate?.id == customer['externalId'] as String,
                    orElse: () => null,
                  )
                  ?.name,
              status: status,
              expiresAt: DateTime.tryParse(
                item['expiresAt']?.toString() ?? '',
              )?.toUtc(),
              issuedBy: item['issuedBy'] as String?,
            ),
          );
          recordsChanged = true;
        }
      }

      var blocksChanged = false;
      final remoteBlocks = snapshot['deviceBlocks'];
      if (remoteBlocks is List) {
        for (final item in remoteBlocks.whereType<Map>()) {
          final deviceId = item['deviceId'];
          final reason = item['reason'];
          if (deviceId is! String ||
              reason is! String ||
              isDeviceBlocked(deviceId)) {
            continue;
          }
          blockedDevices.add(
            BlockedDeviceRecord(
              device: deviceId,
              reason: reason,
              blockedAt:
                  DateTime.tryParse(
                    item['blockedAt']?.toString() ?? '',
                  )?.toUtc() ??
                  DateTime.now().toUtc(),
            ),
          );
          blocksChanged = true;
        }
      }
      if (customersChanged || snapshotReplacedLocal) {
        await prefs!.setStringList(
          _customersKey,
          customers.map((item) => jsonEncode(item.toJson())).toList(),
        );
      }
      if (recordsChanged || snapshotReplacedLocal) {
        if (_consolidateLicenseRecords()) await _saveLicenseRecords();
      }
      if (blocksChanged || snapshotReplacedLocal) await _saveBlockedDevices();
    } on Object {
      // La consola sigue siendo plenamente utilizable sin conectividad.
    }
  }

  Future<String> replaceLicense(
    LicenseRecord current,
    LicensePlan newPlan, {
    int? customDays,
    bool flushSync = true,
  }) async {
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

  bool _consolidateLicenseRecords() {
    final newestByLicense = <String, LicenseRecord>{};
    for (final record in records) {
      final owner = record.customerId ?? 'legacy:${record.device}';
      final key = '$owner|${record.product}';
      final previous = newestByLicense[key];
      if (previous == null || record.issuedAt.isAfter(previous.issuedAt)) {
        newestByLicense[key] = record;
      }
    }
    if (newestByLicense.length == records.length) return false;
    records
      ..clear()
      ..addAll(newestByLicense.values);
    records.sort((a, b) => a.issuedAt.compareTo(b.issuedAt));
    return true;
  }

  Future<void> _saveLicenseRecords() async {
    await prefs!.setStringList(
      _recordsKey,
      records.map((record) => jsonEncode(record.toJson())).toList(),
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

class BlockedDeviceRecord {
  const BlockedDeviceRecord({
    required this.device,
    required this.reason,
    required this.blockedAt,
    this.customerId,
  });

  final String device;
  final String reason;
  final DateTime blockedAt;
  final String? customerId;

  factory BlockedDeviceRecord.fromJson(Map<String, dynamic> json) =>
      BlockedDeviceRecord(
        device: json['device'] as String,
        reason: json['reason'] as String,
        blockedAt: DateTime.parse(json['blockedAt'] as String),
        customerId: json['customerId'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'device': device,
    'reason': reason,
    'blockedAt': blockedAt.toIso8601String(),
    'customerId': customerId,
  };
}

class AdminAccount {
  const AdminAccount({
    this.id,
    required this.email,
    required this.passwordHash,
    this.passwordSalt,
    required this.role,
    this.isActive = true,
  });

  final String? id;
  final String email;
  final String passwordHash;
  final String? passwordSalt;
  final String role;
  final bool isActive;

  factory AdminAccount.fromJson(Map<String, dynamic> json) => AdminAccount(
    id: json['id'] as String?,
    email: json['email'] as String,
    passwordHash: json['passwordHash'] as String,
    passwordSalt: json['passwordSalt'] as String?,
    role: json['role'] as String,
    isActive: json['isActive'] as bool? ?? true,
  );

  factory AdminAccount.fromRemote(Map<dynamic, dynamic> json) => AdminAccount(
    id: json['id'] as String?,
    email: json['email'] as String,
    passwordHash: '',
    role: json['role'] as String? ?? 'super',
    isActive: json['isActive'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'passwordHash': passwordHash,
    'passwordSalt': passwordSalt,
    'role': role,
    'isActive': isActive,
  };
}
