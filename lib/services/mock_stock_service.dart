import 'package:flutter/foundation.dart';
import '../models/part.dart';
import '../models/movement.dart';
import '../models/user_role.dart';
import '../models/new_stock_item.dart';
import '../models/drawer.dart';
import '../models/drawer_stock.dart';

class FirestoreStockService extends ChangeNotifier {
  // --- USUARIOS Y ROLES ---
  final List<AppUser> _users = [
    AppUser(id: '1', name: 'Gabriel', role: UserRole.admin),
    AppUser(id: '2', name: 'Facu', role: UserRole.advancedAdmin),
    AppUser(id: '3', name: 'Juan Pérez (Técnico)', role: UserRole.technician),
    AppUser(id: '4', name: 'Carlos Gómez (Técnico)', role: UserRole.technician),
  ];

  late AppUser _currentUser;

  AppUser get currentUser => _currentUser;
  List<AppUser> get users => List.unmodifiable(_users);

  // --- BASE DE DATOS DE STOCK Y CAJONES ---
  final List<Part> _parts = [];
  final Map<int, Map<String, int>> _drawers =
      {}; // Drawer (1-20) -> {PartId: Qty}
  final List<Movement> _movements = [];
  final List<NewStockItem> _newStockItems = [];

  // Getters de modelos
  List<Part> get parts => List.unmodifiable(_parts);
  List<Movement> get movements => List.unmodifiable(_movements);
  List<NewStockItem> get newStockItems => List.unmodifiable(_newStockItems);

  // Getters de cajones y stocks
  List<Drawer> get drawers =>
      List<Drawer>.generate(20, (index) => Drawer(number: index + 1));

  List<DrawerStock> get stocks {
    final List<DrawerStock> result = [];
    _drawers.forEach((drawerNum, partsMap) {
      partsMap.forEach((partId, qty) {
        if (qty > 0) {
          result.add(DrawerStock(
            drawerNumber: drawerNum,
            partId: partId,
            quantity: qty,
          ));
        }
      });
    });
    return result;
  }

  FirestoreStockService() {
    _currentUser = _users[0];
    _initializeDefaultData();
  }

  void setCurrentUser(AppUser user) {
    _currentUser = user;
    notifyListeners();
  }

  // --- BÚSQUEDA Y COMPATIBILIDAD ---
  Part? findPartByCode(String code) {
    final cleanCode = code.trim().toUpperCase();
    try {
      return _parts.firstWhere(
        (p) => p.partNumber.toUpperCase() == cleanCode || p.id == cleanCode,
      );
    } catch (_) {
      return null;
    }
  }

  List<int> getDrawersForSaving() {
    return List<int>.generate(20, (i) => i + 1);
  }

  Map<int, int> getStockPerDrawerForPart(String partId) {
    return getDrawerBreakdownForPart(partId);
  }

  Map<int, int> getAvailableDrawersForWithdrawal(String partId) {
    return getDrawerBreakdownForPart(partId);
  }

  // --- GESTIÓN DE ROLES ---
  void updateUserRole(String userId, UserRole newRole) {
    if (_currentUser.role != UserRole.advancedAdmin) {
      throw Exception(
          'Permiso denegado: Solo el Admin Avanzado puede cambiar roles.');
    }
    final index = _users.indexWhere((u) => u.id == userId);
    if (index != -1) {
      _users[index] = AppUser(
        id: _users[index].id,
        name: _users[index].name,
        role: newRole,
      );
      notifyListeners();
    }
  }

  // --- 1. AÑADIR A LA BASE DE DATOS (CATÁLOGO ADMINISTRATIVO) ---
  Part addPartToCatalog({
    required String partNumber,
    required String description,
    required List<String> compatibleModels,
    int minStock = 0,
    int maxStock = 0,
  }) {
    if (_currentUser.role == UserRole.technician) {
      throw Exception(
          'Permiso denegado: Los técnicos no pueden añadir piezas al catálogo.');
    }

    final exists = _parts
        .any((p) => p.partNumber.toUpperCase() == partNumber.toUpperCase());
    if (exists) {
      throw Exception('El Part Number "$partNumber" ya existe en el catálogo.');
    }

    final newPart = Part(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      partNumber: partNumber.trim().toUpperCase(),
      description: description.trim(),
      compatibleModels: compatibleModels,
      minStock: minStock,
      maxStock: maxStock,
    );

    _parts.add(newPart);
    notifyListeners();
    return newPart;
  }

  Part addPart({
    required String partNumber,
    required String description,
    required List<String> compatibleModels,
    int minStock = 0,
    int maxStock = 0,
  }) {
    return addPartToCatalog(
      partNumber: partNumber,
      description: description,
      compatibleModels: compatibleModels,
      minStock: minStock,
      maxStock: maxStock,
    );
  }

  // --- 2. MOVIMIENTOS DE STOCK EN CAJONES (OPERATIVO) ---
  void saveStock({
    required String partId,
    required int drawerNumber,
    required int quantity,
    String? userName,
  }) {
    final part = _parts.firstWhere((p) => p.id == partId);

    _drawers.putIfAbsent(drawerNumber, () => <String, int>{});
    final currentQty = _drawers[drawerNumber]![partId] ?? 0;
    _drawers[drawerNumber]![partId] = currentQty + quantity;

    final newTotal = getTotalStockForPart(partId);
    if (part.maxStock > 0 && newTotal >= part.maxStock) {
      part.timesTouchedMax++;
    }

    _movements.add(Movement(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      partNumber: part.partNumber,
      drawerNumber: drawerNumber,
      quantity: quantity,
      type: MovementType.ingreso,
      userName: userName ?? _currentUser.name,
      timestamp: DateTime.now(),
    ));

    notifyListeners();
  }

  void addStock({
    required String partId,
    required int drawerNumber,
    required int quantity,
    String? userName,
  }) {
    saveStock(
      partId: partId,
      drawerNumber: drawerNumber,
      quantity: quantity,
      userName: userName,
    );
  }

  bool withdrawStock({
    required String partId,
    required int drawerNumber,
    required int quantity,
    String? userName,
  }) {
    final part = _parts.firstWhere((p) => p.id == partId);
    final currentQty = _drawers[drawerNumber]?[partId] ?? 0;

    if (currentQty < quantity) return false;

    _drawers[drawerNumber]![partId] = currentQty - quantity;

    final newTotal = getTotalStockForPart(partId);
    if (part.minStock > 0 && newTotal < part.minStock) {
      part.timesTouchedMin++;
    }

    _movements.add(Movement(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      partNumber: part.partNumber,
      drawerNumber: drawerNumber,
      quantity: quantity,
      type: MovementType.retiro,
      userName: userName ?? _currentUser.name,
      timestamp: DateTime.now(),
    ));

    notifyListeners();
    return true;
  }

  // --- 3. ACCIÓN TIPO TRANSFERENCIA ---
  void registerTransfer({
    required String partNumber,
    required String sourceMachine,
    required String targetMachine,
    required int quantity,
  }) {
    _movements.add(Movement(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      partNumber: partNumber.toUpperCase(),
      drawerNumber: 0,
      quantity: quantity,
      type: MovementType.transferencia,
      userName: _currentUser.name,
      timestamp: DateTime.now(),
      sourceMachine: sourceMachine,
      targetMachine: targetMachine,
    ));

    notifyListeners();
  }

  // --- CONSULTAS Y ESTADÍSTICAS ---
  int getTotalStockForPart(String partId) {
    int total = 0;
    _drawers.forEach((_, partsMap) {
      total += partsMap[partId] ?? 0;
    });
    return total;
  }

  Map<int, int> getDrawerBreakdownForPart(String partId) {
    final Map<int, int> breakdown = <int, int>{};
    _drawers.forEach((drawer, partsMap) {
      final qty = partsMap[partId] ?? 0;
      if (qty > 0) breakdown[drawer] = qty;
    });
    return breakdown;
  }

  void updatePartMinStock(String partId, int newMin) {
    if (_currentUser.role == UserRole.technician) {
      throw Exception(
          'Permiso denegado: Los técnicos no pueden editar el stock mínimo.');
    }
    final index = _parts.indexWhere((p) => p.id == partId);
    if (index != -1) {
      _parts[index].minStock = newMin;
      _parts[index].maxStock = ((newMin + 1) + (newMin * 0.5)).ceil();
      notifyListeners();
    }
  }

  Map<String, int> getGlobalMovementStats() {
    int totalOps = _movements.length;
    int totalIngresados = 0;
    int totalRetirados = 0;

    for (var m in _movements) {
      if (m.type == MovementType.ingreso) {
        totalIngresados += m.quantity;
      } else if (m.type == MovementType.retiro) {
        totalRetirados += m.quantity;
      }
    }

    return <String, int>{
      'totalOps': totalOps,
      'totalIngresados': totalIngresados,
      'totalRetirados': totalRetirados,
    };
  }

  List<MapEntry<String, int>> getTopMovedParts({int limit = 5}) {
    final Map<String, int> counts = <String, int>{};
    for (var m in _movements) {
      final current = counts[m.partNumber] ?? 0;
      counts[m.partNumber] = current + m.quantity;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).toList();
  }

  List<MapEntry<String, int>> getTopMovedModels({int limit = 5}) {
    final Map<String, int> modelCounts = <String, int>{};
    for (var m in _movements) {
      final partList = _parts.where(
          (p) => p.partNumber.toUpperCase() == m.partNumber.toUpperCase());
      if (partList.isNotEmpty) {
        for (var model in partList.first.compatibleModels) {
          final current = modelCounts[model] ?? 0;
          modelCounts[model] = current + m.quantity;
        }
      }
    }
    final sorted = modelCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).toList();
  }

  // --- CARGA DE STOCK NUEVOS ---
  void loadNewStockItems(List<NewStockItem> items) {
    if (_currentUser.role == UserRole.technician) {
      throw Exception('Permiso denegado.');
    }
    _newStockItems.clear();
    _newStockItems.addAll(items);
    notifyListeners();
  }

  void _initializeDefaultData() {
    _parts.addAll([
      Part(
        id: '1',
        partNumber: '773429',
        description: 'Tapa superior de escáner MX711',
        compatibleModels: ['MX711', 'MX810'],
        minStock: 2,
        maxStock: 4,
      ),
      Part(
        id: '2',
        partNumber: '881234',
        description: 'Guía de papel ADF',
        compatibleModels: ['MX711', 'MS810'],
        minStock: 5,
        maxStock: 8,
      ),
    ]);

    _drawers[1] = {'1': 2};
    _drawers[5] = {'2': 1};

    _newStockItems.addAll([
      NewStockItem(
        partNumber: '20N4XK0',
        description: 'Toner LX K 6K CS/CX431',
        unit: 'UN',
        currentStock: 338,
        family: 'INSUMOS',
        brand: 'LEXMARK',
      ),
      NewStockItem(
        partNumber: '24B6236',
        description: 'Toner LX 17K MS810 Magnético',
        unit: 'UN',
        currentStock: 3,
        family: 'INSUMOS',
        brand: 'LEXMARK',
      ),
    ]);
  }
}
