class Part {
  final String id;
  final String partNumber;
  final String description;
  final List<String> compatibleModels;
  int minStock;
  int maxStock;
  int timesTouchedMin; // Veces que cayó por debajo del mínimo
  int timesTouchedMax; // Veces que alcanzó/superó el máximo
  int equipmentInPark; // Equipos en parque para la fórmula
  int safeTimeDays;    // Días de reserva (default 60)

  Part({
    required this.id,
    required this.partNumber,
    required this.description,
    required this.compatibleModels,
    this.minStock = 0,
    this.maxStock = 0,
    this.timesTouchedMin = 0,
    this.timesTouchedMax = 0,
    this.equipmentInPark = 0,
    this.safeTimeDays = 60,
  });

  /// Recálculo dinámico de Mínimo según fórmula del Excel:
  /// Min = ROUNDDOWN(SafeTime * (ConsumoTotal / DiasPeriodo))
  void recalculateMinMax({
    required int totalConsumedInPeriod,
    int periodDays = 30,
  }) {
    if (periodDays <= 0) return;

    final double dailyFailureRate = totalConsumedInPeriod / periodDays;
    
    // Mínimo
    minStock = (safeTimeDays * dailyFailureRate).floor();
    
    // Máximo: ROUNDUP((Min + 1) + (Min * 0.5))
    maxStock = ((minStock + 1) + (minStock * 0.5)).ceil();
  }
}