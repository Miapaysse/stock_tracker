enum MovementType {
  ingreso,
  retiro,
  transferencia, // Nueva acción de canibalización entre máquinas
}

class Movement {
  final String id;
  final String partNumber;
  final int drawerNumber; // 0 en caso de transferencia directa
  final int quantity;
  final MovementType type;
  final String userName;
  final DateTime timestamp;
  final String? sourceMachine; // Máquina origen si es transferencia
  final String? targetMachine; // Máquina destino si es transferencia

  Movement({
    required this.id,
    required this.partNumber,
    required this.drawerNumber,
    required this.quantity,
    required this.type,
    required this.userName,
    required this.timestamp,
    this.sourceMachine,
    this.targetMachine,
  });
}