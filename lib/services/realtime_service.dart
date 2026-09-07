import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/enums.dart';

/// Avisos en vivo de movimientos de inventario.
///
/// Realtime ya está habilitado sobre `inventory_movements` desde la primera
/// migración, así que aquí solo hay que escuchar.
///
/// **Agrupa los avisos con un retardo corto**: veinte salidas seguidas en un
/// puesto lanzarían veinte recargas de los agregados del dashboard. Se espera
/// a que se calme y se refresca una vez.
class RealtimeService {
  const RealtimeService();

  static const _channelName = 'invictor:movimientos';

  /// Emite el último movimiento recibido, agrupando ráfagas.
  ///
  /// El payload de Realtime **no pasa por RLS de la misma forma que una
  /// consulta**: llega el registro tal cual se insertó. Por eso solo se usa
  /// como señal de "algo cambió, vuelve a consultar" — los datos que se
  /// muestran salen siempre de las vistas, que sí filtran por puesto.
  Stream<MovementSignal> watchMovements({Duration debounce = const Duration(milliseconds: 700)}) {
    final controller = StreamController<MovementSignal>();
    Timer? timer;
    MovementSignal? pending;

    final channel = Supabase.instance.client.channel(_channelName);

    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: Tables.inventoryMovements,
      callback: (payload) {
        final record = payload.newRecord;
        pending = MovementSignal(
          standId: record['stand_id'] as String?,
          productId: record['product_id'] as String?,
          type: MovementType.fromWire(record['type'] as String?),
          quantity: (record['quantity'] as num?)?.toInt() ?? 0,
          at: DateTime.tryParse(record['created_at']?.toString() ?? '') ??
              DateTime.now(),
        );

        timer?.cancel();
        timer = Timer(debounce, () {
          final signal = pending;
          if (signal != null && !controller.isClosed) {
            controller.add(signal);
          }
          pending = null;
        });
      },
    ).subscribe();

    controller.onCancel = () async {
      timer?.cancel();
      await Supabase.instance.client.removeChannel(channel);
    };

    return controller.stream;
  }
}

/// Señal de que hubo un movimiento. Sirve para refrescar y para avisar.
class MovementSignal {
  const MovementSignal({
    required this.type,
    required this.quantity,
    required this.at,
    this.standId,
    this.productId,
  });

  final String? standId;
  final String? productId;
  final MovementType type;
  final int quantity;
  final DateTime at;

  /// Solo las salidas merecen aviso sonoro: una entrada de mercadería la
  /// registra el propio encargado y no es noticia para él.
  bool get isWorthAlerting => type == MovementType.salida;
}
