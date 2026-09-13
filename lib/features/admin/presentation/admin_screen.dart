import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/tokens.dart';
import '../../../services/service_providers.dart';
import '../../../shared/widgets/app_widgets.dart';
import 'categories_section.dart';
import 'audit_section.dart';
import 'stands_section.dart';
import 'users_section.dart';

/// Administración: puestos, categorías y usuarios.
///
/// Existe para que operar el sistema no dependa del SQL Editor de Supabase.
/// El acceso ya lo limita RLS —crear puestos y cambiar roles es de admin— y
/// esta pantalla solo evita mostrar acciones que la base rechazaría.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).value;

    if (profile == null || !profile.isStaff) {
      return Scaffold(
        appBar: AppBar(title: const Text('Administración')),
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'Sin acceso',
          detail: 'Esta sección es para encargados y administradores.',
        ),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Administración'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Puestos'),
              Tab(text: 'Categorías'),
              Tab(text: 'Usuarios'),
              Tab(text: 'Cambios'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            StandsSection(),
            CategoriesSection(),
            UsersSection(),
            AuditSection(),
          ],
        ),
      ),
    );
  }
}

/// Aviso reutilizable para acciones reservadas a administrador.
class AdminOnlyNotice extends StatelessWidget {
  const AdminOnlyNotice({super.key, required this.what});

  final String what;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.md,
        Space.gutter,
        0,
      ),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              'Puedes consultar, pero $what requiere rol de administrador.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
