part of 'main.dart';

const _productLabels = <String, String>{
  'bdj_studio_sample_pad': 'BDJ Studio Sample Pad',
  'bdj_studio_synth_pro': 'BDJ Studio Synth Pro',
  'bdj_studio_stems_music': 'BDJ Studio Stems Music',
  'bdj_studio_wave_video': 'BDJ Studio Wave Video',
  'bdj_studio_voice_spot': 'BDJ Studio Voice Spot',
  'bdj_studio_search_pro': 'BDJ Studio Search Pro',
  'bdj_studio_audio_analyzer': 'BDJ Studio Audio Analyzer',
};

String _formatDateTime(DateTime dt) {
  final local = dt.toLocal();
  final d = local.day.toString().padLeft(2, '0');
  final m = local.month.toString().padLeft(2, '0');
  final y = local.year.toString();
  final h = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$d/$m/$y $h:$min';
}

String _formatCreator(String? creator) {
  if (creator == null || creator.trim().isEmpty || creator.trim().toLowerCase() == 'super admin') {
    return 'david.zapata';
  }
  final clean = creator.trim();
  if (clean.contains('@')) {
    return clean.split('@').first;
  }
  return clean;
}

extension _LicenseDashboardView on _LicenseHomeState {
  Widget buildDashboardShell(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: wide ? 28 : 16,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.shield_lefthalf_fill, color: Color(0xFF00E5FF)),
            SizedBox(width: 12),
            Text(
              'BDJ Studio License',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          if (wide)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  widget.issuer.currentUser ?? '',
                  style: const TextStyle(color: Colors.white60),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(right: wide ? 16 : 8),
            child: MediaQuery.sizeOf(context).width >= 560
                ? TextButton.icon(
                    onPressed: logout,
                    icon: const Icon(CupertinoIcons.square_arrow_right),
                    label: const Text('Cerrar sesión'),
                  )
                : IconButton(
                    tooltip: 'Cerrar sesión',
                    onPressed: logout,
                    icon: const Icon(CupertinoIcons.square_arrow_right),
                  ),
          ),
        ],
      ),
      body: Row(
        children: [
          if (wide) _dashboardSidebar(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: KeyedSubtree(
                key: ValueKey(selectedSection),
                child: _dashboardSection(),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: wide || !widget.issuer.canDo('usuarios', 'read')
          ? null
          : NavigationBar(
              selectedIndex: selectedSection,
              onDestinationSelected: (value) =>
                  updateDashboard(() => selectedSection = value),
              destinations: const [
                NavigationDestination(
                  icon: Icon(CupertinoIcons.person_2_square_stack_fill),
                  label: 'Gestión',
                ),
                NavigationDestination(
                  icon: Icon(CupertinoIcons.person_crop_circle_badge_checkmark),
                  label: 'Usuarios',
                ),
              ],
            ),
    );
  }

  Widget _dashboardSidebar() {
    final canUsers = widget.issuer.canDo('usuarios', 'read');
    final isCreator = widget.issuer.isSuperAdmin;
    final currentAdmin = widget.issuer.currentAdmin;
    final roleTitle = isCreator
        ? 'Super Administrador'
        : (currentAdmin == null
            ? 'Sin rol'
            : (widget.issuer.findRole(currentAdmin.role).id == currentAdmin.role
                ? widget.issuer.findRole(currentAdmin.role).name
                : currentAdmin.displayRole));
    final roleSubtitle = isCreator
        ? 'Control total (Protegido)'
        : (widget.issuer.canDo('gestion', 'update') || widget.issuer.canDo('gestion', 'delete')
            ? 'Gestión de licencias'
            : (widget.issuer.canDo('gestion', 'create')
                ? 'Crear y buscar licencias'
                : 'Solo lectura'));

    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: Color(0xFF0E121B),
        border: Border(right: BorderSide(color: Color(0xFF1E2530))),
      ),
      padding: const EdgeInsets.fromLTRB(14, 24, 14, 18),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.transparent,
              child: ListTile(
                selected: selectedSection == 0,
                selectedTileColor: const Color(0x335E5CE6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: const Icon(CupertinoIcons.person_2_square_stack_fill),
                title: const Text('Gestión'),
                onTap: () => updateDashboard(() => selectedSection = 0),
              ),
            ),
          ),
          if (canUsers)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.transparent,
                child: ListTile(
                  selected: selectedSection == 1,
                  selectedTileColor: const Color(0x335E5CE6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: const Icon(CupertinoIcons.person_crop_circle_badge_checkmark),
                  title: const Text('Usuarios'),
                  onTap: () => updateDashboard(() => selectedSection = 1),
                ),
              ),
            ),
          const Spacer(),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: isCreator ? const Color(0x3300E5FF) : const Color(0x335E5CE6),
              child: Icon(
                isCreator ? CupertinoIcons.shield_fill : CupertinoIcons.person_fill,
                size: 18,
                color: isCreator ? const Color(0xFF00E5FF) : null,
              ),
            ),
            title: Text(
              roleTitle,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isCreator ? const Color(0xFF00E5FF) : null,
              ),
            ),
            subtitle: Text(
              roleSubtitle,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardSection() {
    if (selectedSection == 1 && !widget.issuer.canDo('usuarios', 'read')) {
      return _managementPage();
    }
    return switch (selectedSection) {
      1 => _usersPage(),
      _ => _managementPage(),
    };
  }

  Widget _dashboardPage({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) => ListView(
    padding: EdgeInsets.all(
      MediaQuery.sizeOf(context).width < 360
          ? 10
          : MediaQuery.sizeOf(context).width < 600
          ? 16
          : 24,
    ),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.white60, fontSize: 15),
              ),
              const SizedBox(height: 24),
              ...children,
              if (error != null) ...[
                const SizedBox(height: 16),
                _dashboardNotice(error!, Colors.redAccent),
              ],
            ],
          ),
        ),
      ),
    ],
  );



  Widget _dashboardPanel(Widget child) => Container(
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 400 ? 14 : 22),
    decoration: BoxDecoration(
      color: const Color(0xFF181824),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFF2A2A3B)),
    ),
    child: child,
  );

  Widget _managementPage() {
    const pageSize = 8;
    final query = customerSearch.text.trim().toLowerCase();
    final filtered = widget.issuer.customers.reversed.where((customer) {
      if (query.isEmpty) return true;
      if (customer.name.toLowerCase().contains(query) ||
          customer.email.toLowerCase().contains(query) ||
          customer.device.toLowerCase().contains(query)) {
        return true;
      }
      final custLicenses = _allActiveLicensesForClient(customer);
      for (final lic in custLicenses) {
        if (lic.product.toLowerCase().contains(query) ||
            lic.productLabel.toLowerCase().contains(query) ||
            lic.planLabel.toLowerCase().contains(query) ||
            lic.plan.toLowerCase().contains(query) ||
            (lic.token != null && lic.token!.toLowerCase().contains(query)) ||
            (lic.exactVersion != null && lic.exactVersion!.toLowerCase().contains(query)) ||
            (lic.issuedBy != null && lic.issuedBy!.toLowerCase().contains(query))) {
          return true;
        }
      }
      return false;
    }).toList();
    final pageCount = max(1, (filtered.length + pageSize - 1) ~/ pageSize);
    final safePage = customerPage.clamp(0, pageCount - 1);
    final visible = filtered.skip(safePage * pageSize).take(pageSize).toList();

    return _dashboardPage(
      title: 'Gestión',
      subtitle:
          'Administra clientes, dispositivos y accesos desde un único formulario.',
      children: [
        _dashboardPanel(
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 620;
              final header = const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Clientes y licencias',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Un dispositivo puede tener una duración y productos propios.',
                    style: TextStyle(color: Colors.white60),
                  ),
                ],
              );
              final actionButtons = Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (widget.issuer.isSuperAdmin)
                    OutlinedButton.icon(
                      onPressed: _exportFullBackupJson,
                      icon: const Icon(CupertinoIcons.arrow_down_doc, size: 16),
                      label: const Text('Exportar Respaldo'),
                    ),
                  if (widget.issuer.canDo('gestion', 'create'))
                    FilledButton.icon(
                      onPressed: () => _showCustomerLicenseModal(),
                      icon: const Icon(CupertinoIcons.add),
                      label: const Text('Nueva licencia'),
                    ),
                ],
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [header, const SizedBox(height: 12), actionButtons],
                );
              }
              return Row(
                children: [
                  Expanded(child: header),
                  actionButtons,
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        _dashboardPanel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 14,
                runSpacing: 12,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Clientes y licencias (${filtered.length})',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(
                    width: MediaQuery.sizeOf(context).width < 560
                        ? double.infinity
                        : 360,
                    child: TextField(
                      controller: customerSearch,
                      onChanged: (_) => updateDashboard(() => customerPage = 0),
                      decoration: const InputDecoration(
                        hintText: 'Buscar por cliente, correo, ID, producto o clave...',
                        prefixIcon: Icon(CupertinoIcons.search),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (visible.isEmpty)
                const _DashboardEmpty(
                  icon: CupertinoIcons.person_2,
                  message: 'No hay clientes para mostrar.',
                )
              else
                ...visible.map(_managementCustomerCard),
              if (filtered.isNotEmpty) ...[
                const Divider(height: 28),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Página ${safePage + 1} de $pageCount',
                      style: const TextStyle(color: Colors.white60),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      tooltip: 'Página anterior',
                      onPressed: safePage == 0
                          ? null
                          : () => updateDashboard(
                              () => customerPage = safePage - 1,
                            ),
                      icon: const Icon(CupertinoIcons.chevron_left),
                    ),
                    IconButton(
                      tooltip: 'Página siguiente',
                      onPressed: safePage >= pageCount - 1
                          ? null
                          : () => updateDashboard(
                              () => customerPage = safePage + 1,
                            ),
                      icon: const Icon(CupertinoIcons.chevron_right),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showCustomerLicenseModal({CustomerRecord? customer}) async {
    final related = customer == null
        ? <CustomerRecord>[]
        : widget.issuer.customers
              .where(
                (item) =>
                    item.email.toLowerCase() == customer.email.toLowerCase() ||
                    item.device.toLowerCase() == customer.device.toLowerCase(),
              )
              .toList();
    final drafts = related
        .map(
          (item) => _DeviceLicenseDraft.fromCustomer(
            item,
            _activeProductsFor(item),
            _activeLicensesFor(item),
          ),
        )
        .toList();
    if (drafts.isEmpty) drafts.add(_DeviceLicenseDraft());

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final wideDialog = MediaQuery.sizeOf(dialogContext).width >= 760;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            insetPadding: EdgeInsets.symmetric(
              horizontal: wideDialog ? 40 : 12,
              vertical: 24,
            ),
            title: Text(
              customer == null
                  ? 'Emitir licencias por dispositivo'
                  : 'Gestionar licencias de dispositivo',
            ),
            content: SizedBox(
              width: wideDialog ? 680 : double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...drafts.asMap().entries.map((entry) {
                      final index = entry.key;
                      final draft = entry.value;
                      return _buildDeviceLicenseDraft(
                        draft: draft,
                        canRemove: drafts.length > 1,
                        onRemove: () => setDialogState(() {
                          final removed = drafts.removeAt(index);
                          removed.dispose();
                        }),
                        onChanged: () => setDialogState(() {}),
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(CupertinoIcons.check_mark),
                label: Text(
                  customer == null ? 'Crear y emitir' : 'Guardar y emitir',
                ),
              ),
            ],
          ),
        );
      },
    );
    if (accepted == true) {
      await _saveCustomerLicenseModal(
        customer?.name ?? '',
        customer?.email ?? '',
        drafts,
        originalCustomerIds: related.map((item) => item.id).toSet(),
      );
    }
    for (final draft in drafts) {
      draft.dispose();
    }
  }

  Set<String> _activeProductsFor(CustomerRecord customer) => widget
      .issuer
      .records
      .where(
        (record) =>
            record.isActive &&
            (record.customerId == customer.id ||
                record.device.toLowerCase() == customer.device.toLowerCase()),
      )
      .map((record) => record.product)
      .toSet();

  List<LicenseRecord> _activeLicensesFor(CustomerRecord customer) => widget
      .issuer
      .records
      .where(
        (record) =>
            record.isActive &&
            (record.customerId == customer.id ||
                record.device.toLowerCase() == customer.device.toLowerCase()),
      )
      .toList();

  Widget _buildDeviceLicenseDraft({
    required _DeviceLicenseDraft draft,
    required bool canRemove,
    required VoidCallback onRemove,
    required VoidCallback onChanged,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF20202D),
      border: Border.all(color: const Color(0xFF303043)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(CupertinoIcons.device_laptop, color: Color(0xFF00E5FF)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                draft.existing == null
                    ? 'Nuevo dispositivo'
                    : 'Dispositivo registrado',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (canRemove)
              IconButton(
                tooltip: 'Quitar dispositivo',
                onPressed: onRemove,
                icon: const Icon(CupertinoIcons.trash, color: Colors.redAccent),
              ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth;
            final wide = available >= 620;
            final half = (available - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: wide ? 390 : available,
                  child: TextField(
                    controller: draft.device,
                    onChanged: (_) => onChanged(),
                    decoration: const InputDecoration(
                      labelText: 'ID de dispositivo',
                      helperText: 'Un ID por dispositivo.',
                    ),
                  ),
                ),
                SizedBox(
                  width: wide ? 180 : half,
                  child: DropdownButtonFormField<LicensePlan>(
                    initialValue: draft.plan,
                    decoration: const InputDecoration(labelText: 'Duración'),
                    items: LicensePlan.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      draft.plan = value ?? LicensePlan.year;
                      onChanged();
                    },
                  ),
                ),
                if (draft.plan == LicensePlan.custom)
                  SizedBox(
                    width: wide ? 130 : half,
                    child: TextField(
                      controller: draft.customDays,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Días'),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        const Text(
          'Productos con acceso',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: _productLabels.entries
              .map(
                (entry) => FilterChip(
                  label: Text(entry.value),
                  selected: draft.products.contains(entry.key),
                  onSelected: (selected) {
                    if (selected) {
                      draft.products.add(entry.key);
                    } else {
                      draft.products.remove(entry.key);
                    }
                    onChanged();
                  },
                ),
              )
              .toList(),
        ),
        if (draft.existingLicenses.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text(
            'Licencias actuales de este dispositivo',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 6),
          ...draft.existingLicenses.map(
            (license) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.checkmark_seal_fill,
                    size: 15,
                    color: Color(0xFF30D158),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${license.productLabel} · Versión ${license.appVersion} · ${license.planLabel} · Creada por: ${_formatCreator(license.issuedBy)}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) {
              final button = OutlinedButton.icon(
                onPressed: () async {
                  final tokens = <String, String>{};
                  for (final license in draft.existingLicenses) {
                    final token = await widget.issuer
                        .generateSpp3TokenForRecord(license);
                    tokens['${license.productLabel} · ${_shortDeviceId(license.device)}'] =
                        token;
                  }
                  if (tokens.isNotEmpty && mounted) {
                    await _showGeneratedCodesDialog(tokens);
                  }
                },
                icon: const Icon(CupertinoIcons.eye, size: 16),
                label: const Text('Ver / copiar licencias'),
              );
              return constraints.maxWidth < 300
                  ? SizedBox(width: double.infinity, child: button)
                  : Align(alignment: Alignment.centerLeft, child: button);
            },
          ),
        ],
      ],
    ),
  );

  Future<void> _saveCustomerLicenseModal(
    String name,
    String email,
    List<_DeviceLicenseDraft> drafts, {
    required Set<String> originalCustomerIds,
  }) async {
    await runWithLoading(
      message: 'Guardando cliente y generando licencias...',
      action: () async {
        try {
          if (drafts.any((draft) => draft.device.text.trim().isEmpty)) {
            throw ArgumentError('Ingresa el ID de activación del dispositivo.');
          }
          final generated = <String, String>{};
          final retainedIds = drafts
              .map((draft) => draft.existing?.id)
              .whereType<String>()
              .toSet();
          for (final customerId in originalCustomerIds.difference(
            retainedIds,
          )) {
            await widget.issuer.deleteCustomer(customerId);
          }
          var pending = drafts.fold<int>(
            0,
            (total, draft) => total + draft.products.length,
          );
          for (final draft in drafts) {
            final effectiveName = name.trim().isNotEmpty
                ? name.trim()
                : 'Dispositivo ${_shortDeviceId(draft.device.text.trim())}';
            final effectiveEmail = email.trim().contains('@')
                ? email.trim()
                : 'device_${_shortDeviceId(draft.device.text.trim())}@bdjstudio.local';
            CustomerRecord? saved;
            if (draft.existing != null) {
              await widget.issuer.updateCustomer(
                draft.existing!.id,
                name: effectiveName,
                email: effectiveEmail,
                device: draft.device.text,
              );
              saved = widget.issuer.customers.cast<CustomerRecord?>().firstWhere(
                (item) => item!.id == draft.existing!.id,
                orElse: () => null,
              );
              if (saved == null) {
                updateDashboard(() => error = 'Cliente no encontrado después de actualizar.');
                return;
              }
            } else {
              saved = await widget.issuer.getOrCreateCustomer(
                effectiveName,
                effectiveEmail,
                draft.device.text,
                flushSync: false,
              );
            }
            final customer = saved;
            if (draft.existing != null) {
              await widget.issuer.setProductAccess(
                customerId: customer.id,
                device: customer.device,
                products: draft.products,
                flushSync: pending == 0,
              );
            }
            for (final product in draft.products) {
              pending--;
              final token = await widget.issuer.issue(
                product,
                saved.device,
                draft.plan,
                customerId: saved.id,
                customDays: draft.plan == LicensePlan.custom
                    ? int.tryParse(draft.customDays.text)
                    : null,
                flushSync: pending == 0,
              );
              generated['${_productLabels[product] ?? product} · ${_shortDeviceId(saved.device)}'] =
                  token;
            }
          }
          updateDashboard(() => error = null);
          if (mounted && generated.isNotEmpty) {
            await _showGeneratedCodesDialog(generated);
          }
        } on Object catch (exception) {
          updateDashboard(() => error = exception.toString());
        }
      },
    );
  }

  Widget _managementCustomerCard(CustomerRecord customer) {
    final activeLicenses = _allActiveLicensesFor(customer);
    final statusColor = activeLicenses.isEmpty
        ? Colors.orangeAccent
        : const Color(0xFF30D158);
    final statusText = activeLicenses.isEmpty
        ? 'Sin licencias'
        : '${activeLicenses.length} Licencia${activeLicenses.length > 1 ? "s" : ""} activa${activeLicenses.length > 1 ? "s" : ""}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF20202D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF303043)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: const Color(0x335E5CE6),
            child: Text(
              customer.name.isEmpty ? '?' : customer.name[0].toUpperCase(),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      customer.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SelectableText(
                      '${customer.email}  ·  ID: ${customer.device}',
                      style: const TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x1F00E5FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0x4D00E5FF),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            CupertinoIcons.calendar,
                            size: 13,
                            color: Color(0xFF00E5FF),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Registro: ${_formatDateTime(customer.createdAt)}',
                            style: const TextStyle(
                              color: Color(0xFF00E5FF),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (activeLicenses.isEmpty)
                  const Text(
                    'Sin licencias activas emitidas.',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '${activeLicenses.length} Licencia(s) activa(s):',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                side: const BorderSide(
                                  color: Colors.cyanAccent,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              onPressed: () async {
                                final tokens = <String, String>{};
                                for (final lic in _allActiveLicensesForClient(
                                  customer,
                                )) {
                                  final token = await widget.issuer
                                      .generateSpp3TokenForRecord(lic);
                                  tokens['${lic.productLabel} · ${_shortDeviceId(lic.device)}'] =
                                      token;
                                }
                                _showGeneratedCodesDialog(tokens);
                              },
                              icon: const Icon(
                                CupertinoIcons.eye_fill,
                                size: 14,
                                color: Colors.cyanAccent,
                              ),
                              label: const Text(
                                'Ver / Copiar Claves',
                                style: TextStyle(
                                  color: Colors.cyanAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...activeLicenses.map((lic) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0x3364D2FF),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0x6664D2FF),
                                  ),
                                ),
                                child: Text(
                                  lic.productLabel,
                                  style: const TextStyle(
                                    color: Color(0xFF00E5FF),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Text(
                                lic.planLabel,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0x1F30D158),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0x4D30D158),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      CupertinoIcons.calendar_today,
                                      size: 13,
                                      color: Color(0xFF30D158),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Emitida: ${_formatDateTime(lic.issuedAt)}',
                                      style: const TextStyle(
                                        color: Color(0xFF30D158),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _buildLicenseExpirationBadge(lic),
                              Text(
                                'Version ${lic.appVersion}',
                                style: const TextStyle(
                                  color: Colors.amberAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0x287C4DFF),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0x667C4DFF),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      CupertinoIcons.person_badge_plus_fill,
                                      size: 13,
                                      color: Color(0xFFC4B5FD),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Creada por: ${_formatCreator(lic.issuedBy)}',
                                      style: const TextStyle(
                                        color: Color(0xFFC4B5FD),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              InkWell(
                                borderRadius: BorderRadius.circular(4),
                                onTap: () async {
                                  final token = await widget.issuer
                                      .generateSpp3TokenForRecord(lic);
                                  Clipboard.setData(ClipboardData(text: token));
                                  if (mounted) {
                                    ScaffoldMessenger.of(
                                      context,
                                    ).clearSnackBars();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Clave SPP3 de ${lic.productLabel} copiada al portapapeles.',
                                        ),
                                        duration: const Duration(seconds: 2),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        CupertinoIcons.doc_on_doc,
                                        size: 14,
                                        color: Colors.cyanAccent,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Copiar',
                                        style: TextStyle(
                                          color: Colors.cyanAccent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (widget.issuer.canDo('gestion', 'delete')) ...[
                                InkWell(
                                  borderRadius: BorderRadius.circular(4),
                                  onTap: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        backgroundColor: const Color(0xFF1E2235),
                                        title: const Text(
                                          'Eliminar Licencia',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                        content: Text(
                                          '¿Deseas eliminar la licencia de "${lic.productLabel}" para ${customer.name}?',
                                          style: const TextStyle(color: Colors.white70),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(ctx).pop(false),
                                            child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
                                          ),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                            onPressed: () => Navigator.of(ctx).pop(true),
                                            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      try {
                                        await widget.issuer.deleteLicense(lic.id);
                                        if (mounted) {
                                          updateDashboard(() {});
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Licencia de ${lic.productLabel} eliminada.'),
                                              duration: const Duration(seconds: 2),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          updateDashboard(() => error = e.toString());
                                        }
                                      }
                                    }
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          CupertinoIcons.trash,
                                          size: 14,
                                          color: Colors.redAccent,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Eliminar',
                                          style: TextStyle(
                                            color: Colors.redAccent,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Acciones',
            onSelected: (action) =>
                _managementAction(action, customer, activeLicenses),
            itemBuilder: (context) => [
              if (activeLicenses.isNotEmpty)
                const PopupMenuItem(
                  value: 'viewKeys',
                  child: ListTile(
                    leading: Icon(
                      CupertinoIcons.eye_fill,
                      color: Colors.cyanAccent,
                    ),
                    title: Text('Ver / Copiar Claves de Licencias'),
                  ),
                ),
              if (widget.issuer.canDo('gestion', 'update'))
                const PopupMenuItem(
                  value: 'manage',
                  child: ListTile(
                    leading: Icon(CupertinoIcons.slider_horizontal_3),
                    title: Text('Gestionar cliente y licencias'),
                  ),
                ),
              if (widget.issuer.canDo('gestion', 'delete'))
                const PopupMenuItem(
                  value: 'deleteCustomer',
                  child: ListTile(
                    leading: Icon(
                      CupertinoIcons.delete_solid,
                      color: Colors.redAccent,
                    ),
                    title: Text('Eliminar cliente'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<LicenseRecord> _allActiveLicensesFor(CustomerRecord customer) {
    final active = <LicenseRecord>[];
    for (final license in widget.issuer.records.reversed) {
      final matchesCustomer =
          (license.customerId != null && license.customerId == customer.id) ||
          (license.device.toLowerCase() == customer.device.toLowerCase());
      if (matchesCustomer && license.isActive) {
        if (!active.any((l) => l.product == license.product)) {
          active.add(license);
        }
      }
    }
    return active;
  }

  /// Reúne las licencias activas de todos los dispositivos asociados a un
  /// cliente. El correo es el vínculo estable entre los registros de cada
  /// dispositivo creados desde el modal único de gestión.
  List<LicenseRecord> _allActiveLicensesForClient(CustomerRecord customer) {
    final deviceIds = widget.issuer.customers
        .where(
          (item) => item.email.toLowerCase() == customer.email.toLowerCase(),
        )
        .map((item) => item.device.toLowerCase())
        .toSet();
    final customerIds = widget.issuer.customers
        .where(
          (item) => item.email.toLowerCase() == customer.email.toLowerCase(),
        )
        .map((item) => item.id)
        .toSet();
    return widget.issuer.records
        .where(
          (license) =>
              license.isActive &&
              (customerIds.contains(license.customerId) ||
                  deviceIds.contains(license.device.toLowerCase())),
        )
        .toList();
  }

  Future<void> _showGeneratedCodesDialog(Map<String, String> tokens) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          title: const Row(
            children: [
              Icon(
                CupertinoIcons.checkmark_seal_fill,
                color: Color(0xFF30D158),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Licencia(s) Generada(s)',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: size.height * 0.52,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: tokens.entries.map((e) {
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141420),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF1E2430)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.key,
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          e.value,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${e.value.length} caracteres · formato esperado: SPP3.<payload>.<cert>.<firma>',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _downloadSingleLicenseTxt(e.key, e.value),
                              icon: const Icon(
                                CupertinoIcons.arrow_down_doc,
                                size: 14,
                                color: Color(0xFF00E5FF),
                              ),
                              label: const Text(
                                'Descargar .txt',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF00E5FF),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: e.value));
                                if (mounted) {
                                  ScaffoldMessenger.of(
                                    context,
                                  ).clearSnackBars();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Clave de ${e.key} copiada.',
                                      ),
                                      duration: const Duration(seconds: 1),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(
                                CupertinoIcons.doc_on_doc,
                                size: 14,
                              ),
                              label: const Text(
                                'Copiar clave',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            if (tokens.length > 1) ...[
              FilledButton.icon(
                onPressed: () => _downloadAllLicensesTxt(tokens),
                icon: const Icon(CupertinoIcons.arrow_down_doc_fill),
                label: const Text('Descargar TODAS en .txt'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final allText = tokens.entries
                      .map((e) => '${e.key}:\n${e.value}')
                      .join('\n\n');
                  await Clipboard.setData(ClipboardData(text: allText));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Todas las claves copiadas al portapapeles.',
                        ),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                icon: const Icon(CupertinoIcons.doc_on_doc_fill),
                label: const Text('Copiar TODAS las claves'),
              ),
            ] else if (tokens.length == 1)
              FilledButton.icon(
                onPressed: () => _downloadSingleLicenseTxt(
                  tokens.keys.first,
                  tokens.values.first,
                ),
                icon: const Icon(CupertinoIcons.arrow_down_doc_fill),
                label: const Text('Descargar archivo .txt'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  /// Completa el guardado del archivo devuelto por `FilePicker.saveFile`.
  ///
  /// En Windows, macOS y Linux el selector solo devuelve la ruta elegida, así
  /// que los bytes hay que escribirlos aquí. En Android e iOS el plugin ya los
  /// escribió a través del selector del sistema y devolver una ruta manipulable
  /// no está garantizado, por lo que no se toca el archivo.
  Future<String> _writeIfDesktop(String outputPath, List<int> payload) async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      return outputPath;
    }
    final file = File(
      outputPath.endsWith('.txt') ? outputPath : '$outputPath.txt',
    );
    await file.writeAsBytes(payload, flush: true);
    return file.path;
  }

  Future<void> _downloadSingleLicenseTxt(String title, String token) async {
    try {
      final cleanName = title
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final defaultFileName = 'Licencia_$cleanName.txt';

      // El contenido va en `bytes` porque desde file_picker 10 es un parámetro
      // obligatorio: en Android el plugin escribe el archivo él mismo a través
      // del selector del sistema (SAF) y sin bytes devuelve null, que es el
      // fallo que veíamos al descargar el .txt en el móvil.
      final payload = utf8.encode(token.trim());

      final outputPath = await FilePicker.saveFile(
        dialogTitle: 'Guardar clave de licencia (.txt)',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: const ['txt'],
        bytes: payload,
      );

      if (outputPath == null || outputPath.isEmpty) {
        return; // El usuario canceló la ventana de guardar
      }

      // En escritorio el plugin solo devuelve la ruta elegida y el archivo lo
      // escribimos nosotros. En Android e iOS ya está escrito, y lo que se
      // devuelve puede ser un content:// que File() no sabe abrir.
      final savedPath = await _writeIfDesktop(outputPath, payload);

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF00E5FF),
            content: Text(
              '¡Licencia guardada en: $savedPath! ✓',
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
            content: Text('Error al guardar archivo: $e'),
          ),
        );
      }
    }
  }

  Future<void> _downloadAllLicensesTxt(Map<String, String> tokens) async {
    try {
      final nowStr = DateTime.now().toIso8601String().split('T').first;
      final defaultFileName = 'Licencias_BDJ_Studio_$nowStr.txt';

      // Indicar claramente el producto y dispositivo para cada clave
      final content = tokens.entries
          .map((entry) => '=== ${entry.key} ===\n${entry.value.trim()}')
          .join('\n\n');
      final payload = utf8.encode(content);

      final outputPath = await FilePicker.saveFile(
        dialogTitle: 'Guardar todas las licencias (.txt)',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: const ['txt'],
        bytes: payload,
      );

      if (outputPath == null || outputPath.isEmpty) {
        return; // El usuario canceló la ventana de guardar
      }

      final savedPath = await _writeIfDesktop(outputPath, payload);

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF00E5FF),
            content: Text(
              '¡Todas las licencias guardadas en: $savedPath! ✓',
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
            content: Text('Error al guardar archivo: $e'),
          ),
        );
      }
    }
  }

  Future<void> _exportFullBackupJson() async {
    try {
      final now = DateTime.now();
      final dateSlug = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final defaultFileName = 'BDJ_Studio_Respaldo_$dateSlug.json';

      final backupData = {
        'version': '1.0.3',
        'export_date': now.toUtc().toIso8601String(),
        'exported_by': widget.issuer.currentUser ?? 'admin',
        'stats': {
          'customers_count': widget.issuer.customers.length,
          'licenses_count': widget.issuer.records.length,
          'admins_count': widget.issuer.admins.length,
        },
        'customers': widget.issuer.customers.map((c) => c.toJson()).toList(),
        'licenses': widget.issuer.records.map((l) => l.toJson()).toList(),
      };

      final jsonContent = const JsonEncoder.withIndent('  ').convert(backupData);
      final payload = utf8.encode(jsonContent);

      final outputPath = await FilePicker.saveFile(
        dialogTitle: 'Exportar respaldo completo de la base de datos (.json)',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: payload,
      );

      if (outputPath == null || outputPath.isEmpty) return;

      if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
        final filePath = outputPath.endsWith('.json') ? outputPath : '$outputPath.json';
        final file = File(filePath);
        await file.writeAsBytes(payload, flush: true);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF00E5FF),
            content: Text(
              '¡Respaldo de seguridad exportado exitosamente! ✓ ($defaultFileName)',
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
            content: Text('Error al exportar respaldo: $e'),
          ),
        );
      }
    }
  }

  Widget _buildLicenseExpirationBadge(LicenseRecord lic) {
    if (lic.expiresAt == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0x2830D158),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0x6630D158)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.infinite, size: 12, color: Color(0xFF30D158)),
            SizedBox(width: 4),
            Text(
              'Permanente',
              style: TextStyle(
                color: Color(0xFF30D158),
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiryDay = DateTime(
      lic.expiresAt!.year,
      lic.expiresAt!.month,
      lic.expiresAt!.day,
    );
    final isExpired = lic.expiresAt!.isBefore(now);
    final daysLeft = expiryDay.difference(today).inDays;

    if (isExpired) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0x28FF453A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0x66FF453A)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.exclamationmark_circle_fill, size: 12, color: Color(0xFFFF453A)),
            const SizedBox(width: 4),
            Text(
              'Expirada (${_dashboardDate(lic.expiresAt!)})',
              style: const TextStyle(
                color: Color(0xFFFF453A),
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    if (daysLeft <= 7) {
      final label = daysLeft <= 0 ? 'Vence hoy' : 'Vence en $daysLeft d';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0x28FF9F0A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0x66FF9F0A)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.clock_fill, size: 12, color: Color(0xFFFF9F0A)),
            const SizedBox(width: 4),
            Text(
              '$label (${_dashboardDate(lic.expiresAt!)})',
              style: const TextStyle(
                color: Color(0xFFFF9F0A),
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0x2800E5FF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x6600E5FF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.calendar, size: 12, color: Color(0xFF00E5FF)),
          const SizedBox(width: 4),
          Text(
            'Vence en $daysLeft d (${_dashboardDate(lic.expiresAt!)})',
            style: const TextStyle(
              color: Color(0xFF00E5FF),
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _usersPage() {
    final isCreator = widget.issuer.isSuperAdmin;
    final activeCount = widget.issuer.admins.where((a) => a.isActive).length;
    final rolesCount = widget.issuer.allRoles.length;

    return _dashboardPage(
      title: 'Usuarios y Roles',
      subtitle: 'Control de acceso basado en roles (RBAC) y gestión de usuarios del sistema.',
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(
            children: [
              FilterChip(
                avatar: const Icon(CupertinoIcons.person_2_fill, size: 16),
                label: Text('Usuarios ($activeCount)'),
                selected: usersSubTab == 0,
                onSelected: (val) {
                  if (val) updateDashboard(() => usersSubTab = 0);
                },
                selectedColor: const Color(0xFF2A3050),
                checkmarkColor: Colors.cyanAccent,
              ),
              const SizedBox(width: 10),
              FilterChip(
                avatar: const Icon(CupertinoIcons.shield_lefthalf_fill, size: 16),
                label: Text('Roles y Permisos ($rolesCount)'),
                selected: usersSubTab == 1,
                onSelected: (val) {
                  if (val) updateDashboard(() => usersSubTab = 1);
                },
                selectedColor: const Color(0xFF2A3050),
                checkmarkColor: Colors.cyanAccent,
              ),
            ],
          ),
        ),
        if (usersSubTab == 0) ...[
          _buildUserCreationPanel(isCreator),
          const SizedBox(height: 18),
          _buildUsersListPanel(isCreator),
        ] else ...[
          _buildRolesAndPermissionsPanel(isCreator),
        ],
      ],
    );
  }

  Widget _buildUserCreationPanel(bool isCreator) {
    return _dashboardPanel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            children: [
              Icon(
                CupertinoIcons.person_crop_circle_badge_plus,
                color: Color(0xFF00E5FF),
              ),
              SizedBox(width: 10),
              Text(
                'Crear Usuario',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 700;
              final fullWidth = narrow ? constraints.maxWidth : null;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: fullWidth ?? 330,
                    child: TextField(
                      controller: adminEmail,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Correo',
                        prefixIcon: Icon(CupertinoIcons.mail_solid),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: fullWidth ?? 300,
                    child: TextField(
                      controller: adminPassword,
                      obscureText: obscureAdminPassword,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(CupertinoIcons.lock_fill),
                        suffixIcon: IconButton(
                          tooltip: obscureAdminPassword ? 'Mostrar clave' : 'Ocultar clave',
                          icon: Icon(
                            obscureAdminPassword ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                          ),
                          onPressed: () => updateDashboard(
                            () => obscureAdminPassword = !obscureAdminPassword,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (isCreator)
                    SizedBox(
                      width: fullWidth ?? 600,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Rol Asignado (RBAC)',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.amberAccent),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ...widget.issuer.allRoles.map((role) {
                                final isSelected = selectedNewAdminRole == role.id ||
                                    (selectedNewAdminRole == 'super' && role.id == 'super_admin');
                                return ChoiceChip(
                                  selected: isSelected,
                                  label: Text(role.name),
                                  avatar: Icon(
                                    role.id.contains('super')
                                        ? CupertinoIcons.shield_fill
                                        : (role.id == 'auditor'
                                            ? CupertinoIcons.eye_fill
                                            : (role.isSystem ? CupertinoIcons.person_badge_plus : CupertinoIcons.slider_horizontal_3)),
                                    size: 15,
                                  ),
                                  selectedColor: role.id.contains('super')
                                      ? const Color(0xFF1E2A3A)
                                      : (role.id == 'operator'
                                          ? const Color(0xFF1E3A2B)
                                          : const Color(0xFF2A2040)),
                                  checkmarkColor: role.id.contains('super')
                                      ? const Color(0xFF00E5FF)
                                      : (role.id == 'operator'
                                          ? const Color(0xFF30D158)
                                          : const Color(0xFFBF5AF2)),
                                  onSelected: (val) {
                                    if (val) {
                                      updateDashboard(() {
                                        selectedNewAdminRole = role.id;
                                        newAdminPermissions = Map<String, Map<String, bool>>.from(
                                          role.permissions.map((k, v) => MapEntry(k, Map<String, bool>.from(v))),
                                        );
                                      });
                                    }
                                  },
                                );
                              }),
                              ChoiceChip(
                                selected: selectedNewAdminRole == 'custom',
                                label: const Text('Personalizado (CRUD)'),
                                avatar: const Icon(CupertinoIcons.slider_horizontal_3, size: 15),
                                onSelected: (val) {
                                  if (val) {
                                    updateDashboard(() {
                                      selectedNewAdminRole = 'custom';
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (selectedNewAdminRole == 'operator')
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0x1A30D158),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0x3330D158)),
                              ),
                              child: const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '✓ Solo verá el módulo de Gestión (podrá crear y buscar licencias y clientes).',
                                    style: TextStyle(color: Color(0xFF30D158), fontSize: 12),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    '✗ NO verá el módulo Usuarios (estará completamente oculto).',
                                    style: TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    '✗ NO podrá eliminar licencias ni eliminar clientes.',
                                    style: TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            )
                          else if (selectedNewAdminRole == 'super' || selectedNewAdminRole == 'super_admin')
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0x1A00E5FF),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0x3300E5FF)),
                              ),
                              child: const Text(
                                '✓ Acceso total al sistema: Gestión completa (crear, buscar, editar, eliminar) y módulo Usuarios.',
                                style: TextStyle(color: Color(0xFF00E5FF), fontSize: 12),
                              ),
                            )
                          else if (selectedNewAdminRole == 'auditor')
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0x1ABF5AF2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0x33BF5AF2)),
                              ),
                              child: const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '✓ Solo lectura: Búsqueda y consulta de clientes y licencias en Gestión.',
                                    style: TextStyle(color: Color(0xFFBF5AF2), fontSize: 12),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    '✗ Sin permisos de creación ni modificación.',
                                    style: TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    '✗ Módulo Usuarios completamente oculto.',
                                    style: TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            )
                          else if (selectedNewAdminRole == 'custom') ...[
                            const SizedBox(height: 6),
                            _permissionsEditor(
                              permissions: newAdminPermissions,
                              onChanged: (module, action, value) {
                                updateDashboard(() {
                                  newAdminPermissions[module]?[action] = value;
                                });
                              },
                            ),
                          ] else
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0x1AFF9F0A),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0x33FF9F0A)),
                              ),
                              child: Text(
                                widget.issuer.findRole(selectedNewAdminRole).description,
                                style: const TextStyle(color: Color(0xFFFF9F0A), fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                  SizedBox(
                    height: 50,
                    width: narrow ? constraints.maxWidth : null,
                    child: FilledButton.icon(
                      onPressed: addAdmin,
                      icon: const Icon(CupertinoIcons.add),
                      label: const Text('Crear usuario'),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildUsersListPanel(bool isCreator) {
    return _dashboardPanel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Usuarios con acceso',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ...(() {
            final activeList = widget.issuer.admins.where((admin) => admin.isActive).toList();
            final me = widget.issuer.currentAdmin;
            if (activeList.isEmpty && me != null) activeList.add(me);
            return activeList;
          })().map((admin) {
            final adminEmail = admin.email.trim().toLowerCase();
            final currentEmail = (widget.issuer.currentUser ?? '').trim().toLowerCase();
            final isCurrent = adminEmail == currentEmail;
            final isCreatorAdmin = admin.role == 'super_admin';
            final isLoggedUserCreator = widget.issuer.isSuperAdmin;

            final leading = CircleAvatar(
              backgroundColor: isCreatorAdmin ? const Color(0xFF00E5FF).withValues(alpha: 0.15) : null,
              child: Icon(
                isCreatorAdmin ? CupertinoIcons.shield_fill : CupertinoIcons.person_fill,
                color: isCreatorAdmin ? const Color(0xFF00E5FF) : null,
              ),
            );
            final title = Text(
              admin.email,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isCreatorAdmin ? const Color(0xFF00E5FF) : null,
              ),
            );
            final permSummary = !isCreatorAdmin && admin.role == 'custom' && admin.permissions != null
                ? _buildPermissionSummary(admin.permissions!)
                : null;
            final subtitle = isCreatorAdmin
                ? Text(
                    isCurrent ? 'Super Administrador · Sesión actual' : 'Super Administrador (Protegido)',
                    style: TextStyle(color: Color(0xFF00E5FF), fontSize: 12),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isCurrent)
                        const Text(
                          'Sesión actual',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ?permSummary,
                    ],
                  );
            final actions = <Widget>[
              // Cada usuario cambia su propia contraseña (Supabase Auth). Los
              // restablecimientos de terceros se hacen desde el panel de Supabase.
              if (isCurrent)
                TextButton.icon(
                  onPressed: () => _showChangePasswordDialog(admin),
                  icon: const Icon(CupertinoIcons.lock_shield, size: 16),
                  label: const Text('Cambiar contraseña'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF5E5CE6),
                  ),
                ),
              // Solo el creador puede editar permisos o reasignar roles de otros usuarios (no del creador mismo)
              if (isLoggedUserCreator && !isCreatorAdmin)
                TextButton.icon(
                  onPressed: () => _showEditPermissionsDialog(admin),
                  icon: const Icon(CupertinoIcons.checkmark_shield, size: 16),
                  label: const Text('Rol y Permisos'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.amberAccent,
                  ),
                ),
              // Solo se puede eliminar si NO es el creador ni la sesión actual, y si el usuario logueado es Creador o tiene permiso de borrado en usuarios
              if (!isCreatorAdmin &&
                  !isCurrent &&
                  (isLoggedUserCreator || widget.issuer.canDo('usuarios', 'delete')))
                IconButton(
                  tooltip: 'Eliminar Usuario',
                  icon: const Icon(
                    CupertinoIcons.trash,
                    size: 18,
                    color: Colors.redAccent,
                  ),
                  onPressed: () => _deleteAdmin(admin),
                ),
            ];
            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 560) {
                  return ListTile(
                    leading: leading,
                    title: title,
                    subtitle: subtitle,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _roleBadge(admin.role, admin.email),
                        const SizedBox(width: 8),
                        ...actions,
                      ],
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          leading,
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                title,
                                subtitle,
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _roleBadge(admin.role, admin.email),
                        ],
                      ),
                      Wrap(children: actions),
                    ],
                  ),
                );
              },
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRolesAndPermissionsPanel(bool isCreator) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dashboardPanel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(CupertinoIcons.shield_lefthalf_fill, color: Color(0xFF00E5FF)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Roles y Permisos del Sistema (RBAC)',
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'El control de acceso basado en roles define con precisión las operaciones CRUD autorizadas en cada módulo.',
                          style: TextStyle(color: Colors.white60, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  if (isCreator)
                    FilledButton.icon(
                      onPressed: _showCreateCustomRoleDialog,
                      icon: const Icon(CupertinoIcons.plus_circle_fill, size: 16),
                      label: const Text('Nuevo Rol'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        ...widget.issuer.allRoles.map((role) {
          final isSys = role.isSystem;
          final roleColor = role.id.contains('super')
              ? const Color(0xFF00E5FF)
              : (role.id == 'operator'
                  ? const Color(0xFF30D158)
                  : (role.id == 'auditor' ? const Color(0xFFBF5AF2) : const Color(0xFFFF9F0A)));

          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _dashboardPanel(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: roleColor.withValues(alpha: 0.18),
                        child: Icon(
                          role.id.contains('super')
                              ? CupertinoIcons.shield_fill
                              : (role.id == 'auditor'
                                  ? CupertinoIcons.eye_fill
                                  : (role.isSystem ? CupertinoIcons.person_badge_plus : CupertinoIcons.slider_horizontal_3)),
                          size: 16,
                          color: roleColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              role.name,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              role.description,
                              style: const TextStyle(fontSize: 12, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSys ? const Color(0x2200E5FF) : const Color(0x22FF9F0A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSys ? const Color(0x6600E5FF) : const Color(0x66FF9F0A),
                          ),
                        ),
                        child: Text(
                          role.id == 'super_admin' ? 'Sistema (Inmutable)' : (isSys ? 'Sistema' : 'Personalizado'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isSys ? const Color(0xFF00E5FF) : const Color(0xFFFF9F0A),
                          ),
                        ),
                      ),
                      if (role.id != 'super_admin' && isCreator) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Editar permisos del rol',
                          icon: const Icon(CupertinoIcons.pencil, size: 16, color: Colors.amberAccent),
                          onPressed: () => _showEditCustomRoleDialog(role),
                        ),
                        if (!isSys)
                          IconButton(
                            tooltip: 'Eliminar rol',
                            icon: const Icon(CupertinoIcons.trash, size: 16, color: Colors.redAccent),
                            onPressed: () => _deleteCustomRole(role),
                          ),
                      ],
                    ],
                  ),
                  const Divider(height: 24, color: Color(0xFF232738)),
                  const Text(
                    'Matriz de Permisos Autorizados:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white54),
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 600;
                      return Wrap(
                        spacing: 20,
                        runSpacing: 12,
                        children: AppModule.all.map((mod) {
                          final modPerms = role.permissions[mod.id] ??
                              role.permissions[mod.id == 'usuarios' ? 'admins' : mod.id] ??
                              {};
                          return Container(
                            width: isNarrow ? constraints.maxWidth : (constraints.maxWidth - 20) / 2,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF131722),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF1E2433)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(mod.icon, size: 14, color: const Color(0xFF00E5FF)),
                                    const SizedBox(width: 8),
                                    Text(
                                      mod.name,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: AppModule.availableActions.map((act) {
                                    final allowed = modPerms[act] ?? false;
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: allowed ? const Color(0x2630D158) : const Color(0x15FFFFFF),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: allowed ? const Color(0x6630D158) : const Color(0x22FFFFFF),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            allowed ? CupertinoIcons.check_mark : CupertinoIcons.xmark,
                                            size: 11,
                                            color: allowed ? const Color(0xFF30D158) : Colors.white38,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            AppModule.actionLabels[act] ?? act,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: allowed ? const Color(0xFF30D158) : Colors.white38,
                                              fontWeight: allowed ? FontWeight.w600 : FontWeight.normal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Future<void> _deleteAdmin(AdminAccount admin) async {
    if (admin.role == 'super_admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Un Super Administrador no puede ser eliminado.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    final adminId = admin.id ?? admin.email;
    final confirmed = await _confirmAction(
      title: 'Eliminar Administrador',
      message: '${admin.email} perder\u00e1 el acceso a esta aplicaci\u00f3n.',
      confirmLabel: 'Eliminar',
    );
    if (!confirmed) return;
    await runWithLoading(
      message: 'Eliminando Administrador...',
      action: () async {
        try {
          await widget.issuer.deleteAdmin(adminId);
          updateDashboard(() => error = null);
        } on Object catch (exception) {
          updateDashboard(() => error = exception.toString());
        }
      },
    );
  }

  Future<void> _showChangePasswordDialog(AdminAccount admin) async {
    final isSelf = admin.email.trim().toLowerCase() ==
        (widget.issuer.currentUser ?? '').trim().toLowerCase();

    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    bool hideCurrent = true;
    bool hideNew = true;
    bool hideConfirm = true;
    String? errorText;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF181824),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(
                CupertinoIcons.lock_shield_fill,
                color: Color(0xFF5E5CE6),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isSelf
                      ? 'Cambiar contraseña'
                      : 'Restablecer contraseña (${admin.email})',
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isSelf) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0x2200E5FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0x5500E5FF)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          CupertinoIcons.info_circle_fill,
                          color: Color(0xFF00E5FF),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Como Creador, estás asignando una nueva contraseña a ${admin.email} sin requerir su contraseña anterior.',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (isSelf) ...[
                  TextField(
                    controller: currentController,
                    obscureText: hideCurrent,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Contraseña actual',
                      labelStyle: const TextStyle(color: Colors.white70),
                      suffixIcon: IconButton(
                        icon: Icon(
                          hideCurrent
                              ? CupertinoIcons.eye_slash
                              : CupertinoIcons.eye,
                          color: Colors.white60,
                        ),
                        onPressed: () =>
                            setDialogState(() => hideCurrent = !hideCurrent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: newController,
                  obscureText: hideNew,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Nueva contraseña',
                    labelStyle: const TextStyle(color: Colors.white70),
                    suffixIcon: IconButton(
                      icon: Icon(
                        hideNew ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                        color: Colors.white60,
                      ),
                      onPressed: () => setDialogState(() => hideNew = !hideNew),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  obscureText: hideConfirm,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Confirmar nueva contraseña',
                    labelStyle: const TextStyle(color: Colors.white70),
                    suffixIcon: IconButton(
                      icon: Icon(
                        hideConfirm
                            ? CupertinoIcons.eye_slash
                            : CupertinoIcons.eye,
                        color: Colors.white60,
                      ),
                      onPressed: () =>
                          setDialogState(() => hideConfirm = !hideConfirm),
                    ),
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorText!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Colors.white60),
              ),
            ),
            FilledButton(
              onPressed: () async {
                final current = currentController.text;
                final next = newController.text;
                final confirm = confirmController.text;

                if (isSelf && current.isEmpty) {
                  setDialogState(
                    () => errorText = 'Ingresa tu contraseña actual.',
                  );
                  return;
                }
                if (next.isEmpty || confirm.isEmpty) {
                  setDialogState(
                    () => errorText = 'Ingresa y confirma la nueva contraseña.',
                  );
                  return;
                }
                if (next != confirm) {
                  setDialogState(
                    () => errorText = 'Las contraseñas no coinciden.',
                  );
                  return;
                }
                if (next.length < 8) {
                  setDialogState(
                    () => errorText =
                        'La contraseña debe tener al menos 8 caracteres.',
                  );
                  return;
                }

                if (ctx.mounted) Navigator.pop(ctx);
                await runWithLoading(
                  message: 'Actualizando contraseña en el servidor...',
                  action: () async {
                    final ok = await widget.issuer.changeAdminPassword(
                      admin.email,
                      isSelf ? current : null,
                      next,
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? (isSelf
                                    ? 'Contraseña actualizada correctamente.'
                                    : 'Contraseña de ${admin.email} restablecida correctamente.')
                                : 'La contraseña actual es incorrecta o falló la actualización.',
                          ),
                          backgroundColor: ok
                              ? const Color(0xFF30D158)
                              : Colors.redAccent,
                        ),
                      );
                      if (ok) updateDashboard(() {});
                    }
                  },
                );
              },
              child: Text(isSelf ? 'Actualizar' : 'Restablecer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _managementAction(
    String action,
    CustomerRecord customer,
    List<LicenseRecord> activeLicenses,
  ) async {
    switch (action) {
      case 'viewKeys':
        final tokens = <String, String>{};
        for (final lic in _allActiveLicensesForClient(customer)) {
          final token = await widget.issuer.generateSpp3TokenForRecord(lic);
          tokens['${lic.productLabel} · ${_shortDeviceId(lic.device)}'] = token;
        }
        if (tokens.isNotEmpty) {
          await _showGeneratedCodesDialog(tokens);
        }
        return;
      case 'manage':
        await _showCustomerLicenseModal(customer: customer);
        return;
      case 'deleteCustomer':
        final confirmed = await _confirmAction(
          title: 'Eliminar cliente',
          message:
              'Se eliminar\u00e1 a ${customer.name} y todas sus licencias asociadas. Esta acci\u00f3n no se puede deshacer.',
          confirmLabel: 'Eliminar',
        );
        if (!confirmed) return;
        await runWithLoading(
          message: 'Eliminando cliente...',
          action: () async {
            try {
              await widget.issuer.deleteCustomer(customer.id);
              updateDashboard(() => error = null);
            } on Object catch (exception) {
              updateDashboard(() => error = exception.toString());
            }
          },
        );
        return;
    }
  }

  // ignore: unused_element
  Future<void> _editCustomerDialog(CustomerRecord customer) async {
    final name = TextEditingController(text: customer.name);
    final email = TextEditingController(text: customer.email);
    final device = TextEditingController(text: customer.device);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Editar cliente'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: email,
                decoration: const InputDecoration(labelText: 'Correo'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: device,
                decoration: const InputDecoration(
                  labelText: 'ID de dispositivo',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await runWithLoading(
        message: 'Guardando datos del cliente...',
        action: () async {
          try {
            await widget.issuer.updateCustomer(
              customer.id,
              name: name.text,
              email: email.text,
              device: device.text,
            );
            updateDashboard(() => error = null);
          } on Object catch (exception) {
            updateDashboard(() => error = exception.toString());
          }
        },
      );
    }
    name.dispose();
    email.dispose();
    device.dispose();
  }

  Widget _permissionsEditor({
    required Map<String, Map<String, bool>> permissions,
    required void Function(String module, String action, bool value) onChanged,
    bool compact = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Permisos por Módulo y Acción',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.amberAccent),
            ),
          ),
        ...AppModule.all.map((mod) {
          final modulePerms = permissions[mod.id] ?? permissions[mod.id == 'usuarios' ? 'admins' : mod.id] ?? {};
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(mod.icon, size: 14, color: const Color(0xFF00E5FF)),
                    const SizedBox(width: 6),
                    Text(
                      mod.name,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: AppModule.availableActions.map((action) {
                    final enabled = modulePerms[action] ?? false;
                    return FilterChip(
                      selected: enabled,
                      label: Text(
                        AppModule.actionLabels[action] ?? action,
                        style: TextStyle(
                          fontSize: 12,
                          color: enabled ? Colors.cyanAccent : Colors.white60,
                        ),
                      ),
                      onSelected: (val) => onChanged(mod.id, action, val),
                      selectedColor: const Color(0xFF1E2A3A),
                      checkmarkColor: Colors.cyanAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  void _showCreateCustomRoleDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final perms = <String, Map<String, bool>>{
      for (final mod in AppModule.all)
        mod.id: {
          for (final act in AppModule.availableActions) act: false,
        },
    };

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E2235),
          title: const Text('Nuevo Rol Personalizado', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre del Rol', hintText: 'Ej. Supervisor de Soporte'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(labelText: 'Descripción', hintText: 'Breve explicación de las funciones'),
                  ),
                  const SizedBox(height: 16),
                  const Text('Permisos por Módulo y Acción:', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  _permissionsEditor(
                    permissions: perms,
                    compact: true,
                    onChanged: (mod, act, val) {
                      setDialogState(() {
                        perms[mod]?[act] = val;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.of(ctx).pop();
                final id = 'role_${DateTime.now().millisecondsSinceEpoch}';
                final newRole = AppRole(
                  id: id,
                  name: name,
                  description: descCtrl.text.trim(),
                  permissions: perms,
                  isSystem: false,
                );
                try {
                  await widget.issuer.saveCustomRole(newRole);
                } on Object catch (e) {
                  updateDashboard(() => error = e.toString());
                  return;
                }
                if (mounted) {
                  updateDashboard(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Rol "$name" creado correctamente.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: const Text('Crear Rol'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditCustomRoleDialog(AppRole role) {
    final nameCtrl = TextEditingController(text: role.name);
    final descCtrl = TextEditingController(text: role.description);
    final perms = Map<String, Map<String, bool>>.from(
      role.permissions.map((k, v) => MapEntry(k, Map<String, bool>.from(v))),
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E2235),
          title: Text('Editar Rol: ${role.name}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre del Rol'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(labelText: 'Descripción'),
                  ),
                  const SizedBox(height: 16),
                  const Text('Permisos por Módulo y Acción:', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  _permissionsEditor(
                    permissions: perms,
                    compact: true,
                    onChanged: (mod, act, val) {
                      setDialogState(() {
                        perms[mod]?[act] = val;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.of(ctx).pop();
                final updated = AppRole(
                  id: role.id,
                  name: name,
                  description: descCtrl.text.trim(),
                  permissions: perms,
                  isSystem: role.isSystem,
                );
                try {
                  await widget.issuer.saveCustomRole(updated);
                } on Object catch (e) {
                  updateDashboard(() => error = e.toString());
                  return;
                }
                if (mounted) {
                  updateDashboard(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Rol "$name" actualizado.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteCustomRole(AppRole role) async {
    final confirmed = await _confirmAction(
      title: 'Eliminar Rol',
      message: '¿Estás seguro de eliminar el rol "${role.name}"? Los usuarios que tengan asignado este rol deberán reasignarse.',
      confirmLabel: 'Eliminar',
    );
    if (!confirmed) return;
    try {
      await widget.issuer.deleteCustomRole(role.id);
    } on Object catch (e) {
      updateDashboard(() => error = e.toString());
      return;
    }
    if (mounted) {
      updateDashboard(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rol "${role.name}" eliminado.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showEditPermissionsDialog(AdminAccount admin) {
    String currentEditRole = admin.role;
    final initialRole = widget.issuer.findRole(currentEditRole);
    final editPerms = Map<String, Map<String, bool>>.from(
      (admin.permissions ?? initialRole.permissions).map(
        (k, v) => MapEntry(k, Map<String, bool>.from(v)),
      ),
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E2235),
          title: Text(
            'Rol y Permisos de ${admin.email}',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Asignar Rol (RBAC):',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.amberAccent),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...widget.issuer.allRoles.map((role) {
                        final isSelected = currentEditRole == role.id ||
                            (currentEditRole == 'super' && role.id == 'super_admin') ||
                            (currentEditRole == 'super_admin' && role.id == 'super_admin');
                        return ChoiceChip(
                          selected: isSelected,
                          label: Text(role.name),
                          avatar: Icon(
                            role.id.contains('super')
                                ? CupertinoIcons.shield_fill
                                : (role.id == 'auditor'
                                    ? CupertinoIcons.eye_fill
                                    : (role.isSystem ? CupertinoIcons.person_badge_plus : CupertinoIcons.slider_horizontal_3)),
                            size: 14,
                          ),
                          selectedColor: role.id.contains('super')
                              ? const Color(0xFF1E2A3A)
                              : (role.id == 'operator'
                                  ? const Color(0xFF1E3A2B)
                                  : const Color(0xFF2A2040)),
                          checkmarkColor: role.id.contains('super')
                              ? const Color(0xFF00E5FF)
                              : (role.id == 'operator'
                                  ? const Color(0xFF30D158)
                                  : const Color(0xFFBF5AF2)),
                          onSelected: (val) {
                            if (val) {
                              setDialogState(() {
                                currentEditRole = role.id;
                                editPerms
                                  ..clear()
                                  ..addAll(role.permissions);
                              });
                            }
                          },
                        );
                      }),
                      ChoiceChip(
                        selected: currentEditRole == 'custom',
                        label: const Text('Personalizado (CRUD)'),
                        avatar: const Icon(CupertinoIcons.slider_horizontal_3, size: 14),
                        onSelected: (val) {
                          if (val) {
                            setDialogState(() {
                              currentEditRole = 'custom';
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (currentEditRole == 'operator')
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0x1A30D158),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0x3330D158)),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('✓ Solo módulo de Gestión (crear y buscar licencias).', style: TextStyle(color: Color(0xFF30D158), fontSize: 12)),
                          SizedBox(height: 2),
                          Text('✗ Módulo Usuarios totalmente oculto.', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          SizedBox(height: 2),
                          Text('✗ No puede eliminar clientes ni licencias.', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    )
                  else if (currentEditRole == 'super' || currentEditRole == 'super_admin')
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0x1A00E5FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0x3300E5FF)),
                      ),
                      child: const Text(
                        '✓ Acceso total al sistema: Gestión completa y Usuarios.',
                        style: TextStyle(color: Color(0xFF00E5FF), fontSize: 12),
                      ),
                    )
                  else if (currentEditRole == 'auditor')
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0x1ABF5AF2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0x33BF5AF2)),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('✓ Solo lectura: Búsqueda y consulta en Gestión.', style: TextStyle(color: Color(0xFFBF5AF2), fontSize: 12)),
                          SizedBox(height: 2),
                          Text('✗ Sin permisos de creación ni modificación.', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          SizedBox(height: 2),
                          Text('✗ Módulo Usuarios totalmente oculto.', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    )
                  else if (currentEditRole == 'custom')
                    _permissionsEditor(
                      permissions: editPerms,
                      compact: true,
                      onChanged: (module, action, value) {
                        setDialogState(() {
                          editPerms[module]?[action] = value;
                        });
                      },
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0x1AFF9F0A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0x33FF9F0A)),
                      ),
                      child: Text(
                        widget.issuer.findRole(currentEditRole).description,
                        style: const TextStyle(color: Color(0xFFFF9F0A), fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                try {
                  final finalPerms = currentEditRole == 'custom'
                      ? editPerms
                      : widget.issuer.findRole(currentEditRole).permissions;
                  await widget.issuer.updateAdmin(
                    admin.id ?? admin.email,
                    email: admin.email,
                    role: currentEditRole,
                    permissions: finalPerms,
                  );
                  if (mounted) {
                    updateDashboard(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Rol de ${admin.email} actualizado.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    updateDashboard(() => error = e.toString());
                  }
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildPermissionSummary(Map<String, Map<String, bool>> perms) {
    final denied = <String>[];
    for (final module in AppModule.all) {
      final mp = perms[module.id] ?? perms[module.id == 'usuarios' ? 'admins' : module.id];
      if (mp == null) continue;
      for (final action in AppModule.availableActions) {
        if (mp[action] != true) {
          denied.add('${module.name}: ${AppModule.actionLabels[action] ?? action}');
        }
      }
    }
    if (denied.isEmpty) return null;
    return Text(
      'Sin permiso: ${denied.join(', ')}',
      style: const TextStyle(color: Colors.orange, fontSize: 11),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _roleBadge([String? role, String? email]) {
    final isSuper = role == 'super' || role == 'super_admin';
    final isLicenseAdmin = role == 'license_admin';
    final isOperator = role == 'operator';
    final isAuditor = role == 'auditor';

    Color bg;
    Color fg;
    String label;

    if (isSuper) {
      bg = const Color(0x3300E5FF);
      fg = const Color(0xFF00E5FF);
      label = 'Super Administrador';
    } else if (isLicenseAdmin) {
      bg = const Color(0x335E5CE6);
      fg = const Color(0xFF8E8CFF);
      label = 'Admin. de Licencias';
    } else if (isOperator) {
      bg = const Color(0x3330D158);
      fg = const Color(0xFF30D158);
      label = 'Operador de Licencias';
    } else if (isAuditor) {
      bg = const Color(0x33BF5AF2);
      fg = const Color(0xFFBF5AF2);
      label = 'Auditor';
    } else {
      final customRole = widget.issuer.findRole(role ?? '');
      bg = const Color(0x33FF9F0A);
      fg = const Color(0xFFFF9F0A);
      label = customRole.isSystem ? 'Personalizado' : customRole.name;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.5), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  String _customerDisplayName(LicenseRecord record) {
    final id = record.customerId;
    if (id != null) {
      for (final customer in widget.issuer.customers) {
        if (customer.id == id) return customer.name;
      }
    }
    return record.customerName ?? 'Cliente anterior';
  }

  // ignore: unused_element
  Widget _licenseTile(LicenseRecord record) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
    leading: const CircleAvatar(
      backgroundColor: Color(0x337D5CFF),
      child: Icon(CupertinoIcons.ticket_fill, color: Color(0xFF9D8CFF)),
    ),
    title: Text(
      _customerDisplayName(record),
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      '${record.productLabel}  ·  ${record.planLabel}\n${record.device}',
    ),
    isThreeLine: true,
    trailing: Text(
      _dashboardDate(record.issuedAt),
      style: const TextStyle(color: Colors.white54),
    ),
  );

  Widget _dashboardNotice(String message, Color color) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: .35)),
    ),
    child: Row(
      children: [
        Icon(CupertinoIcons.exclamationmark_triangle_fill, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ],
    ),
  );

  String _dashboardDate(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}

class _DashboardEmpty extends StatelessWidget {
  const _DashboardEmpty({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Column(
      children: [
        Icon(icon, size: 36, color: Colors.white24),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54),
        ),
      ],
    ),
  );
}

class _DeviceLicenseDraft {
  _DeviceLicenseDraft({
    this.existing,
    Set<String>? products,
    List<LicenseRecord>? existingLicenses,
  }) : products = products ?? <String>{},
       existingLicenses = existingLicenses ?? <LicenseRecord>[],
       device = TextEditingController(text: existing?.device ?? ''),
       customDays = TextEditingController();

  factory _DeviceLicenseDraft.fromCustomer(
    CustomerRecord customer,
    Set<String> products,
    Iterable<LicenseRecord> licenses,
  ) {
    final activeLicenses = licenses.toList(growable: false);
    final draft = _DeviceLicenseDraft(
      existing: customer,
      products: products,
      existingLicenses: activeLicenses,
    );
    final currentPlans = activeLicenses
        .map(
          (license) => LicensePlan.values.where((plan) {
            return plan.name == license.plan;
          }).firstOrNull,
        )
        .whereType<LicensePlan>()
        .toSet();
    // La licencia permanente no tiene fecha de vencimiento. Priorizarla evita
    // que un dispositivo ya permanente se abra erróneamente como "1 año".
    if (activeLicenses.any((license) => license.expiresAt == null) ||
        currentPlans.contains(LicensePlan.permanent)) {
      draft.plan = LicensePlan.permanent;
    } else if (currentPlans.length == 1) {
      draft.plan = currentPlans.single;
    }
    return draft;
  }

  final CustomerRecord? existing;
  final TextEditingController device;
  final TextEditingController customDays;
  LicensePlan plan = LicensePlan.permanent;
  final Set<String> products;
  final List<LicenseRecord> existingLicenses;

  void dispose() {
    device.dispose();
    customDays.dispose();
  }
}
