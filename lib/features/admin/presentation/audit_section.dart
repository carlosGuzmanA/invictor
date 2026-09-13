import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/audit_entry.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../providers/admin_providers.dart';

/// Quién cambió qué y cuándo.
///
/// El stock ya era auditable: cada movimiento guarda su autor y no se puede
/// borrar. Esto cubre el otro lado —el catálogo, los roles, los puestos—,
/// que hasta ahora no dejaba rastro de ningún tipo.
class AuditSection extends ConsumerWidget {
  const AuditSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registro = ref.watch(auditLogProvider);
    final theme = Theme.of(context);

    return registro.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyState(
        icon: Icons.error_outline,
        title: 'No se pudo cargar el registro',
        detail: e is AppException ? e.message : '$e',
        tone: EmptyTone.danger,
        onAction: () => ref.invalidate(auditLogProvider),
      ),
      data: (lista) {
        if (lista.isEmpty) {
          return const EmptyState(
            icon: Icons.history_outlined,
            title: 'Sin cambios registrados',
            detail: 'Aquí aparecerá cada cambio en productos, usuarios, '
                'puestos y categorías, con quién lo hizo.',
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(auditLogProvider),
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: Space.xxl),
            itemCount: lista.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.all(Space.gutter),
                  child: Text(
                    'Cambios en productos, usuarios, puestos y categorías. '
                    'Las ventas y las entradas están en Movimientos: ese '
                    'historial ya era imborrable.',
                    style: theme.textTheme.bodySmall,
                  ),
                );
              }
              return _Fila(entrada: lista[i - 1]);
            },
          ),
        );
      },
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.entrada});

  final AuditEntry entrada;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.semantic;

    final (icono, color) = switch (entrada.action) {
      'insert' => (Icons.add, semantic.positive),
      'delete' => (Icons.delete_outline, semantic.danger),
      _ => (Icons.edit, semantic.info),
    };

    final detalle = entrada.summary;

    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Icon(icono, size: 18, color: color),
      ),
      title: Text(
        '${entrada.actor} ${entrada.actionLabel} '
        '${entrada.tableLabel.toLowerCase()}'
        '${entrada.recordName != null ? ' «${entrada.recordName}»' : ''}',
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Text(
        [
          Fmt.dateTime(entrada.createdAt),
          if (detalle.isNotEmpty) detalle,
        ].join(' · '),
        style: theme.textTheme.labelSmall,
      ),
      // El detalle completo solo si hay algo que enseñar: abrir un diálogo
      // para ver un jsonb vacío es peor que no poder abrirlo.
      onTap: entrada.changed == null || entrada.changed!.isEmpty
          ? null
          : () => _mostrarDetalle(context),
      trailing: entrada.changed == null
          ? null
          : Icon(Icons.chevron_right,
              size: 18, color: theme.colorScheme.outline),
    );
  }

  void _mostrarDetalle(BuildContext context) {
    final theme = Theme.of(context);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${entrada.actor} ${entrada.actionLabel}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(Fmt.dateTime(entrada.createdAt),
                  style: theme.textTheme.labelSmall),
              const SizedBox(height: Space.md),
              for (final campo in entrada.changed!.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: _Campo(nombre: campo.key, valor: campo.value),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

/// Un campo cambiado, con su antes y su después.
class _Campo extends StatelessWidget {
  const _Campo({required this.nombre, required this.valor});

  final String nombre;
  final Object? valor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // En un cambio el valor viene como {antes, ahora}; en un alta o una baja
    // es el valor a secas.
    final esCambio = valor is Map &&
        (valor as Map).containsKey('antes') &&
        (valor as Map).containsKey('ahora');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AuditEntry.fieldLabel(nombre), style: theme.textTheme.labelMedium),
        if (esCambio)
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: _texto((valor as Map)['antes']),
                style: theme.textTheme.bodySmall?.copyWith(
                  decoration: TextDecoration.lineThrough,
                  color: theme.colorScheme.outline,
                ),
              ),
              const TextSpan(text: '  →  '),
              TextSpan(
                text: _texto((valor as Map)['ahora']),
                style: theme.textTheme.bodySmall,
              ),
            ]),
          )
        else
          Text(_texto(valor), style: theme.textTheme.bodySmall),
      ],
    );
  }

  static String _texto(Object? v) => switch (v) {
        null => '—',
        true => 'sí',
        false => 'no',
        _ => '$v',
      };
}
