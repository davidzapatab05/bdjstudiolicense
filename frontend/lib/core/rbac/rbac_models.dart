import 'package:flutter/cupertino.dart';

/// Módulos disponibles en el sistema BDJ Studio License.
class AppModule {
  const AppModule({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
  });

  final String id;
  final String name;
  final String description;
  final IconData icon;

  static const gestion = AppModule(
    id: 'gestion',
    name: 'Gestión de Licencias',
    description: 'Emisión, consulta, renovación y administración de clientes y licencias de software.',
    icon: CupertinoIcons.person_2_square_stack_fill,
  );

  static const usuarios = AppModule(
    id: 'usuarios',
    name: 'Usuarios y Roles',
    description: 'Control de acceso, administración de usuarios y configuración de permisos (RBAC).',
    icon: CupertinoIcons.person_crop_circle_badge_checkmark,
  );

  static const List<AppModule> all = [gestion, usuarios];

  static const List<String> availableActions = ['create', 'read', 'update', 'delete'];

  static const Map<String, String> actionLabels = {
    'create': 'Crear',
    'read': 'Buscar / Ver',
    'update': 'Actualizar',
    'delete': 'Eliminar',
  };

  static const Map<String, String> actionDescriptions = {
    'create': 'Permite emitir o registrar nuevos elementos.',
    'read': 'Permite buscar, listar y consultar la información.',
    'update': 'Permite modificar datos existentes.',
    'delete': 'Permite dar de baja o eliminar registros.',
  };
}

/// Rol en el sistema con permisos por módulo y acción.
class AppRole {
  const AppRole({
    required this.id,
    required this.name,
    required this.description,
    required this.permissions,
    this.isSystem = false,
  });

  final String id;
  final String name;
  final String description;
  final Map<String, Map<String, bool>> permissions;
  final bool isSystem;

  /// Super Administrador: Acceso total e irrestricto a todo el sistema.
  static const superAdmin = AppRole(
    id: 'super_admin',
    name: 'Super Administrador',
    description: 'Acceso total e irrestricto a todos los módulos y operaciones del sistema (Creador).',
    isSystem: true,
    permissions: {
      'gestion': {'create': true, 'read': true, 'update': true, 'delete': true},
      'usuarios': {'create': true, 'read': true, 'update': true, 'delete': true},
    },
  );

  /// Administrador de Licencias: Control total de licencias (Crear, Buscar, Actualizar, Eliminar). Sin acceso al módulo de Usuarios.
  static const licenseAdmin = AppRole(
    id: 'license_admin',
    name: 'Administrador de Licencias',
    description: 'Acceso completo al módulo de Gestión de Licencias (Crear, Buscar, Actualizar, Eliminar). Sin acceso al módulo de Usuarios.',
    isSystem: true,
    permissions: {
      'gestion': {'create': true, 'read': true, 'update': true, 'delete': true},
      'usuarios': {'create': false, 'read': false, 'update': false, 'delete': false},
    },
  );

  /// Operador de Licencias: Solo crear y buscar licencias en Gestión.
  static const operator = AppRole(
    id: 'operator',
    name: 'Operador de Licencias',
    description: 'Solo crear y buscar licencias en Gestión. No puede actualizar ni eliminar registros, ni acceder a Usuarios.',
    isSystem: true,
    permissions: {
      'gestion': {'create': true, 'read': true, 'update': false, 'delete': false},
      'usuarios': {'create': false, 'read': false, 'update': false, 'delete': false},
    },
  );

  /// Auditor: Solo lectura y búsqueda de licencias.
  static const auditor = AppRole(
    id: 'auditor',
    name: 'Auditor (Solo Lectura)',
    description: 'Búsqueda y consulta de licencias y clientes. Sin permisos de modificación ni acceso a usuarios.',
    isSystem: true,
    permissions: {
      'gestion': {'create': false, 'read': true, 'update': false, 'delete': false},
      'usuarios': {'create': false, 'read': false, 'update': false, 'delete': false},
    },
  );

  static const List<AppRole> systemRoles = [superAdmin, licenseAdmin, operator, auditor];

  /// Resuelve si este rol autoriza la acción en el módulo indicado.
  bool hasPermission(String module, String action) {
    final m = (module == 'admins') ? 'usuarios' : module;
    final modPerms = permissions[m] ?? permissions[module];
    if (modPerms == null) return false;
    return modPerms[action] ?? false;
  }

  factory AppRole.fromJson(Map<String, dynamic> json) {
    final rawPerms = json['permissions'];
    final perms = <String, Map<String, bool>>{};
    if (rawPerms is Map) {
      for (final entry in rawPerms.entries) {
        if (entry.value is Map) {
          perms[entry.key.toString()] = {
            for (final e in (entry.value as Map).entries)
              e.key.toString(): e.value == true,
          };
        }
      }
    }
    return AppRole(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      permissions: perms,
      isSystem: json['isSystem'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'permissions': permissions,
    'isSystem': isSystem,
  };

  /// Genera una plantilla de permisos vacía.
  static Map<String, Map<String, bool>> emptyPermissions() => {
    for (final module in AppModule.all)
      module.id: {
        for (final action in AppModule.availableActions) action: false,
      },
  };

  /// Genera una plantilla con todos los permisos habilitados.
  static Map<String, Map<String, bool>> allPermissions() => {
    for (final module in AppModule.all)
      module.id: {
        for (final action in AppModule.availableActions) action: true,
      },
  };
}
