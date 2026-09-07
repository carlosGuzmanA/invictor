import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/enums.dart';
import '../data/models/profile.dart';

/// Quién tiene la aplicación abierta ahora mismo.
///
/// Usa Supabase Presence, que no necesita tabla ni migración: cada cliente
/// publica su estado en un canal y los demás lo reciben.
///
/// **Qué significa exactamente:** "tiene la app abierta", no "está
/// trabajando". Si un vendedor bloquea el teléfono o cierra la pestaña,
/// desaparece de la lista aunque siga en su puesto. Presentarlo como control
/// de turnos llevaría a conclusiones falsas.
class PresenceService {
  const PresenceService();

  static const channelName = 'invictor:presencia';

  /// Abre el canal, publica quién soy y emite la lista cada vez que cambia.
  ///
  /// El `track` va **después** de que el canal confirme la suscripción: antes
  /// de eso el servidor descarta el estado y el usuario no aparecería.
  Stream<List<OnlineUser>> watch(Profile me) {
    final controller = StreamController<List<OnlineUser>>();
    final channel = Supabase.instance.client.channel(channelName);

    void emit() {
      if (controller.isClosed) return;
      controller.add(_parse(channel.presenceState()));
    }

    channel
        .onPresenceSync((_) => emit())
        .onPresenceJoin((_) => emit())
        .onPresenceLeave((_) => emit())
        .subscribe((status, error) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await channel.track({
          'profile_id': me.id,
          'name': me.displayName,
          'role': me.role.wireValue,
          'online_at': DateTime.now().toIso8601String(),
        });
      }
    });

    controller.onCancel = () async {
      // Puede que el canal ya esté muerto —cierre de sesión, pérdida de red—
      // y entonces `untrack` lanza. Que falle aquí no debe propagarse: la
      // salida limpia la hace `AuthService.signOut()` antes de invalidar el
      // token, y esto es solo el respaldo.
      try {
        await channel.untrack();
      } catch (_) {}
      try {
        await Supabase.instance.client.removeChannel(channel);
      } catch (_) {}
    };

    return controller.stream;
  }

  /// Aplana el estado del canal a una lista de usuarios.
  ///
  /// Un mismo usuario puede tener varias entradas —móvil y escritorio, o dos
  /// pestañas—; se deduplica por `profile_id` para no contarlo dos veces.
  List<OnlineUser> _parse(List<SinglePresenceState> state) {
    final byProfile = <String, OnlineUser>{};

    for (final entry in state) {
      for (final presence in entry.presences) {
        final payload = presence.payload;
        final id = payload['profile_id'] as String?;
        if (id == null) continue;

        final user = OnlineUser(
          profileId: id,
          name: (payload['name'] as String?) ?? 'Sin nombre',
          role: UserRole.fromWire(payload['role'] as String?),
          onlineAt:
              DateTime.tryParse(payload['online_at']?.toString() ?? ''),
          devices: 1,
        );

        final existing = byProfile[id];
        byProfile[id] = existing == null
            ? user
            : user.copyWith(devices: existing.devices + 1);
      }
    }

    final list = byProfile.values.toList()
      // Vendedores primero: son los que interesa ver conectados.
      ..sort((a, b) {
        final byRole = a.role.index.compareTo(b.role.index);
        return byRole != 0 ? -byRole : a.name.compareTo(b.name);
      });
    return list;
  }
}

/// Un usuario con la aplicación abierta.
class OnlineUser {
  const OnlineUser({
    required this.profileId,
    required this.name,
    required this.role,
    required this.devices,
    this.onlineAt,
  });

  final String profileId;
  final String name;
  final UserRole role;

  /// Cuántas sesiones tiene abiertas (móvil y escritorio, o dos pestañas).
  final int devices;

  final DateTime? onlineAt;

  OnlineUser copyWith({int? devices}) => OnlineUser(
        profileId: profileId,
        name: name,
        role: role,
        devices: devices ?? this.devices,
        onlineAt: onlineAt,
      );
}
