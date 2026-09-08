library;

/// Enumeraciones espejo de los tipos definidos en PostgreSQL.
///
/// Los `wireValue` DEBEN coincidir exactamente con los enums del esquema
/// (`supabase/migrations/0001_schema.sql`). Si cambias uno, cambia el otro.

/// Roles del sistema (§9 de propuesta.md).
enum UserRole {
  admin('admin', 'Administrador'),
  encargado('encargado', 'Encargado'),
  vendedor('vendedor', 'Vendedor');

  const UserRole(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static UserRole fromWire(String? value) => UserRole.values.firstWhere(
        (r) => r.wireValue == value,
        orElse: () => UserRole.vendedor,
      );

  bool get isAdmin => this == UserRole.admin;

  /// admin o encargado: acceso ampliado a todos los puestos.
  bool get isStaff => this == UserRole.admin || this == UserRole.encargado;
}

/// Tipo de ubicación física.
enum StandType {
  puesto('puesto', 'Puesto'),
  carrito('carrito', 'Carrito'),
  bodega('bodega', 'Bodega'),
  otro('otro', 'Otro');

  const StandType(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static StandType fromWire(String? value) => StandType.values.firstWhere(
        (t) => t.wireValue == value,
        orElse: () => StandType.otro,
      );
}

/// Tipos de movimiento de inventario.
///
/// `quantity` en la base SIEMPRE se guarda positiva; el signo lo determina
/// este tipo. Por eso `ajuste` está dividido en positivo y negativo.
enum MovementType {
  entrada('entrada', 'Entrada', 1),
  salida('salida', 'Salida', -1),
  devolucion('devolucion', 'Devolución', 1),
  ajustePositivo('ajuste_positivo', 'Ajuste (+)', 1),
  ajusteNegativo('ajuste_negativo', 'Ajuste (−)', -1),
  trasladoEntrada('traslado_entrada', 'Traslado recibido', 1),
  trasladoSalida('traslado_salida', 'Traslado enviado', -1);

  const MovementType(this.wireValue, this.label, this.sign);
  final String wireValue;
  final String label;

  /// +1 suma al stock, -1 resta.
  final int sign;

  static MovementType fromWire(String? value) =>
      MovementType.values.firstWhere(
        (t) => t.wireValue == value,
        orElse: () => MovementType.salida,
      );

  bool get isIncoming => sign > 0;

  /// Movimientos que un vendedor puede registrar directamente en su puesto.
  static const operationalTypes = [entrada, salida, devolucion];
}

/// Estado de una jornada de inventario (§8).
enum InventoryStatus {
  abierto('abierto', 'Abierto'),
  finalizado('finalizado', 'Finalizado'),
  anulado('anulado', 'Anulado');

  const InventoryStatus(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static InventoryStatus fromWire(String? value) =>
      InventoryStatus.values.firstWhere(
        (s) => s.wireValue == value,
        orElse: () => InventoryStatus.abierto,
      );

  bool get isOpen => this == InventoryStatus.abierto;
}

/// Estado de una encomienda enviada a un puesto.
///
/// No hay bodega: el administrador compra la mercadería y la despacha en el
/// momento. Al recibirla se generan movimientos de `entrada`, porque es la
/// primera vez que entra al sistema.
enum ShipmentStatus {
  enviado('enviado', 'Enviada'),
  recibido('recibido', 'Recibida'),
  anulado('anulado', 'Anulada');

  const ShipmentStatus(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static ShipmentStatus fromWire(String? value) =>
      ShipmentStatus.values.firstWhere(
        (s) => s.wireValue == value,
        orElse: () => ShipmentStatus.enviado,
      );

  /// Todavía no confirmada por el puesto: es lo que el vendedor debe atender.
  bool get isPending => this == ShipmentStatus.enviado;
}
