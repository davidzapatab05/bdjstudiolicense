import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Rutas privadas y persistentes de BDJ Studio License.
///
/// En cada plataforma la raíz de datos es el directorio de soporte que
/// proporciona `path_provider` (una sola carpeta por OS); los plugins
/// (preferencias, almacén seguro) escriben en la misma carpeta. En móvil
/// permanece dentro del sandbox de la aplicación, sin permisos de archivos.
class AppStorageService {
  AppStorageService._();

  static const _brand = 'BDJ Studio';
  static const _app = 'BDJ Studio License';
  static const _folders = [
    'Database',
    'Projects',
    'Templates',
    'Assets',
    'Cache',
    'Waveforms',
    'Exports',
    'Licenses',
    'Logs',
    'Recovery',
    'Settings',
    'Temp',
    'Thumbnails',
  ];

  static Future<Directory>? _support;

  static Future<Directory> root() async {
    final support = await (_support ??= getApplicationSupportDirectory());
    return Directory(support.path).create(recursive: true);
  }

  static Future<Directory> directory(String name) async =>
      Directory(p.join((await root()).path, name)).create(recursive: true);

  static Future<void> initialize() async {
    if (kIsWeb) return;
    final support = await (_support ??= getApplicationSupportDirectory());
    // Primero el almacén de plugins: sus archivos dejan el support no vacío y
    // sobreviven a la fusión de `_migrateDesktopRoot`.
    await _migrateLegacyPluginSupport(support);
    await _migrateDesktopRoot(support);
    await root();
    await Future.wait(_folders.map(directory));
  }

  static Future<void> clearPersistentData() async {
    if (kIsWeb) return;
    final directory = await root();
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  /// Nombres de carpeta de soporte que usaban builds antiguas (ProductName del
  /// exe o application id de Linux). Sus archivos de plugins se migran al
  /// support actual para no dejar datos huérfanos.
  static const _legacyPluginSupportNames = [
    'bdj_studio_license',
    'com.bdjstudio.bdj_license_console',
  ];

  /// Migra los datos que los plugins guardaban en rutas de soporte heredadas
  /// hacia la carpeta de soporte actual. Sin esto, al cambiar el nombre del
  /// soporte (ProductName del exe / application id) se perderían las
  /// preferencias y la licencia (flutter_secure_storage.dat + shared_preferences.json).
  static Future<void> _migrateLegacyPluginSupport(Directory support) async {
    if (!Platform.isWindows && !Platform.isLinux) return;
    final candidates = <Directory>[];
    for (final name in _legacyPluginSupportNames) {
      candidates
        ..add(Directory(p.join(support.parent.path, name)))
        ..add(Directory(p.join(support.parent.parent.path, name)))
        ..add(Directory(p.join(support.parent.parent.path, _brand, name)))
        ..add(
          Directory(p.join(support.parent.parent.path, 'com.bdjstudio', name)),
        );
    }
    for (final legacy in candidates) {
      if (legacy.path == support.path || !await legacy.exists()) continue;
      try {
        await support.create(recursive: true);
        for (final fileName in const [
          'flutter_secure_storage.dat',
          'shared_preferences.json',
        ]) {
          final source = File(p.join(legacy.path, fileName));
          if (!await source.exists()) continue;
          final target = File(p.join(support.path, fileName));
          if (await target.exists()) continue;
          await source.rename(target.path);
        }
        await _deleteIfEmpty(legacy);
      } catch (e) {
        debugPrint(
          'AppStorage: no se pudo migrar datos de plugins desde ${legacy.path}: $e',
        );
      }
    }
  }

  static Future<void> _migrateDesktopRoot(Directory support) async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;
    final target = support;
    // La raíz de datos es el support dir. Ubicaciones antiguas (carpeta de
    // marca anidada, duplicada, o en la raíz del padre) se fusionan al support
    // para que quede una sola carpeta por OS.
    final candidates = [
      Directory(p.join(support.path, _app)),
      Directory(p.join(support.path, _brand, _app)),
      Directory(p.join(support.parent.path, _app)),
      // Ruta duplicada que creó una versión anterior (base/marca/marca/App)
      // cuando el support ya vivía bajo la marca: se corrige a base/marca/App.
      Directory(p.join(support.parent.path, _brand, _app)),
      // Bases de datos antiguas de otra empresa o raíz plana (p.ej. un build
      // con CompanyName distinto, o data guardada sin carpeta de marca).
      Directory(p.join(support.parent.parent.path, _app)),
      Directory(p.join(support.parent.parent.path, _brand, _app)),
    ];
    for (final legacy in candidates) {
      if (legacy.path == target.path || !await legacy.exists()) continue;
      try {
        await target.create(recursive: true);
        await _moveInto(legacy, target);
        // Nunca borrar la raíz del padre; solo carpetas intermedias vacías.
        if (legacy.parent.path != support.parent.path) {
          await _deleteIfEmpty(legacy.parent);
        }
      } catch (e) {
        debugPrint(
          'AppStorage: no se pudo migrar datos desde ${legacy.path}: $e',
        );
      }
    }
  }

  /// Mueve el contenido de [source] hacia [target] sin sobrescribir entradas
  /// que ya existan, y borra [source] si quedó vacía. Permite fusionar la data
  /// de una ubicación antigua dentro del support aunque éste ya tenga archivos
  /// (p.ej. las preferencias de plugins guardadas por path_provider).
  static Future<void> _moveInto(Directory source, Directory target) async {
    await for (final entry in source.list()) {
      final dest = p.join(target.path, p.basename(entry.path));
      if (await FileSystemEntity.type(dest) != FileSystemEntityType.notFound) {
        continue;
      }
      await entry.rename(dest);
    }
    await _deleteIfEmpty(source);
  }

  static Future<void> _deleteIfEmpty(Directory directory) async {
    if (await directory.exists() && (await directory.list().isEmpty)) {
      await directory.delete();
    }
  }
}
