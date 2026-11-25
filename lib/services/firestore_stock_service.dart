import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/part.dart';
import '../models/movement.dart';
import '../models/user_role.dart';
import '../models/new_stock_item.dart';
import '../models/drawer.dart';
import '../models/drawer_stock.dart';

class FirestoreStockService extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final List<AppUser> _users = [];
  late AppUser _currentUser;
  bool _isInitialized = false;

  final List<Part> _parts = [];
  final Map<int, Map<String, int>> _drawers = {}; // Drawer (1-20) -> {PartId: Qty}
  final List<Movement> _movements = [];
  final List<NewStockItem> _newStockItems = [];

  final List<StreamSubscription> _subscriptions = [];

  AppUser get currentUser => _currentUser;
  List<AppUser> get users => List.unmodifiable(_users);
  bool get isInitialized => _isInitialized;

  List<Part> get parts => List.unmodifiable(_parts);
  List<Movement> get movements => List.unmodifiable(_movements);
  List<NewStockItem> get newStockItems => List.unmodifiable(_newStockItems);

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
    // Usuario temporal mientras cargan los datos de Firestore
    _currentUser = AppUser(id: '1', name: 'Gabriel', role: UserRole.admin);
    _initFirestore();
  }

  Future<void> _initFirestore() async {
    await _seedInitialDataIfEmpty();
    _listenToCollections();
  }

  /// Carga datos base en Firestore únicamente si la base de datos está vacía
  Future<void> _seedInitialDataIfEmpty() async {
    final usersSnap = await _db.collection('users').limit(1).get();
    if (usersSnap.docs.isEmpty) {
      final batch = _db.batch();

      final initialUsers = [
        AppUser(id: '1', name: 'Gabriel', role: UserRole.admin),
        AppUser(id: '2', name: 'Facu', role: UserRole.advancedAdmin),
        AppUser(id: '3', name: 'Juan Pérez (Técnico)', role: UserRole.technician),
        AppUser(id: '4', name: 'Carlos Gómez (Técnico)', role: UserRole.technician),
      ];

      for (var u in initialUsers) {
        batch.set(_db.collection('users').doc(u.id), {
          'name': u.name,
          'role': u.role.name,
        });
      }

      // Crear los 20 cajones
      for (int i = 1; i <= 20; i++) {
        Map<String, int> initialContents = {};
        if (i == 1) initialContents = {'773429': 2};
        if (i == 5) initialContents = {'881234': 1};

        batch.set(_db.collection('drawers').doc('drawer_$i'), {
          'drawerNumber': i,
          'contents': initialContents,
        });
      }

      // Catálogo inicial
      batch.set(_db.collection('parts').doc('773429'), {
        'partNumber': '773429',
        'description': 'Tapa superior de escáner MX711',
        'compatibleModels': ['MX711', 'MX810'],
        'minStock': 2,
        'maxStock': 4,
        'safeTimeDays': 60,
        'timesTouchedMin': 0,
        'timesTouchedMax': 0,
      });

      batch.set(_db.collection('parts').doc('881234'), {
        'partNumber': '881234',
        'description': 'Guía de papel ADF',
        'compatibleModels': ['MX711', 'MS810'],
        'minStock': 5,
        'maxStock': 8,
        'safeTimeDays': 60,
        'timesTouchedMin': 0,
        'timesTouchedMax': 0,
      });

      await batch.commit();
    }
  }

  void _listenToCollections() {
    // 1. Escuchar Usuarios
    _subscriptions.add(
      _db.collection('users').snapshots().listen((snapshot) {
        _users.clear();
        for (var doc in snapshot.docs) {
          final data = doc.data();
          final roleStr = data['role'] as String? ?? 'technician';
          final role = UserRole.values.firstWhere(
            (r) => r.name == roleStr,
            orElse: () => UserRole.technician,
          );
          _users.add(AppUser(
            id: doc.id,
            name: data['name'] ?? 'Usuario',
            role: role,
          ));
        }
        if (_users.isNotEmpty) {
          final match = _users.where((u) => u.id == _currentUser.id);
          _currentUser = match.isNotEmpty ? match.first : _users.first;
        }
        _isInitialized = true;
        notifyListeners();
      }),
    );

    // 2. Escuchar Catálogo de Repuestos (parts)
    _subscriptions.add(
      _db.collection('parts').snapshots().listen((snapshot) {
        _parts.clear();
        for (var doc in snapshot.docs) {
          final data = doc.data();
          _parts.add(Part(
            id: doc.id,
            partNumber: data['partNumber'] ?? doc.id,
            description: data['description'] ?? '',
            compatibleModels: List<String>.from(data['compatibleModels'] ?? []),
            minStock: (data['minStock'] as num?)?.toInt() ?? 0,
            maxStock: (data['maxStock'] as num?)?.toInt() ?? 0,
            safeTimeDays: (data['safeTimeDays'] as num?)?.toInt() ?? 60,
            timesTouchedMin: (data['timesTouchedMin'] as num?)?.toInt() ?? 0,
            timesTouchedMax: (data['timesTouchedMax'] as num?)?.toInt() ?? 0,
          ));
        }
        notifyListeners();
      }),
    );

    // 3. Escuchar Cajones (drawers)
    _subscriptions.add(
      _db.collection('drawers').snapshots().listen((snapshot) {
        _drawers.clear();
        for (var doc in snapshot.docs) {
          final data = doc.data();
          final drawerNum = (data['drawerNumber'] as num?)?.toInt() ?? 0;
          final rawContents = Map<String, dynamic>.from(data['contents'] ?? {});
          final parsedContents = <String, int>{};
          rawContents.forEach((partId, qty) {
            final intQty = (qty as num?)?.toInt() ?? 0;
            if (intQty > 0) parsedContents[partId] = intQty;
          });
          if (drawerNum > 0) {
            _drawers[drawerNum] = parsedContents;
          }
        }
        notifyListeners();
      }),
    );

    // 4. Escuchar Historial de Movimientos
    _subscriptions.add(
      _db
          .collection('movements')
          .orderBy('timestamp', descending: false)
          .limitToLast(200)
          .snapshots()
          .listen((snapshot) {
        _movements.clear();
        for (var doc in snapshot.docs) {
          final data = doc.data();
          final typeStr = data['type'] as String? ?? 'ingreso';
          final type = MovementType.values.firstWhere(
            (t) => t.name == typeStr,
            orElse: () => MovementType.ingreso,
          );
          final ts = data['timestamp'];
          final dateTime = ts is Timestamp ? ts.toDate() : DateTime.now();

          _movements.add(Movement(
            id: doc.id,
            partNumber: data['partNumber'] ?? '',
            drawerNumber: (data['drawerNumber'] as num?)?.toInt() ?? 0,
            quantity: (data['quantity'] as num?)?.toInt() ?? 0,
            type: type,
            userName: data['userName'] ?? '',
            timestamp: dateTime,
            sourceMachine: data['sourceMachine'],
            targetMachine: data['targetMachine'],
          ));
        }
        notifyListeners();
      }),
    );

    // 5. Escuchar Stock Nuevos (Compras)
    _subscriptions.add(
      _db.collection('new_stock').snapshots().listen((snapshot) {
        _newStockItems.clear();
        for (var doc in snapshot.docs) {
          final data = doc.data();
          _newStockItems.add(NewStockItem(
            partNumber: data['partNumber'] ?? doc.id,
            description: data['description'] ?? '',
            unit: data['unit'] ?? 'UN',
            currentStock: (data['currentStock'] as num?)?.toInt() ?? 0,
            family: data['family'] ?? '',
            brand: data['brand'] ?? '',
          ));
        }
        notifyListeners();
      }),
    );
  }

  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
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
        (p) => p.partNumber.toUpperCase() == cleanCode || p.id.toUpperCase() == cleanCode,
      );
    } catch (_) {
      return null;
    }
  }

  List<int> getDrawersForSaving() => List<int>.generate(20, (i) => i + 1);

  Map<int, int> getStockPerDrawerForPart(String partId) =>
      getDrawerBreakdownForPart(partId);

  Map<int, int> getAvailableDrawersForWithdrawal(String partId) =>
      getDrawerBreakdownForPart(partId);

  // --- GESTIÓN DE ROLES ---
  Future<void> updateUserRole(String userId, UserRole newRole) async {
    if (_currentUser.role != UserRole.advancedAdmin) {
      throw Exception('Permiso denegado: Solo el Admin Avanzado puede cambiar roles.');
    }
    await _db.collection('users').doc(userId).update({'role': newRole.name});
  }

  // --- 1. AÑADIR A LA BASE DE DATOS (CATÁLOGO) ---
  Part addPartToCatalog({
    required String partNumber,
    required String description,
    required List<String> compatibleModels,
    int minStock = 0,
    int maxStock = 0,
  }) {
    if (_currentUser.role == UserRole.technician) {
      throw Exception('Permiso denegado: Los técnicos no pueden añadir piezas al catálogo.');
    }

    final cleanPn = partNumber.trim().toUpperCase();
    final exists = _parts.any((p) => p.partNumber.toUpperCase() == cleanPn);
    if (exists) {
      throw Exception('El Part Number "$cleanPn" ya existe en el catálogo.');
    }

    final newPart = Part(
      id: cleanPn,
      partNumber: cleanPn,
      description: description.trim(),
      compatibleModels: compatibleModels,
      minStock: minStock,
      maxStock: maxStock,
    );

    _parts.add(newPart);
    notifyListeners();

    _db.collection('parts').doc(cleanPn.replaceAll('/', '_')).set({
      'partNumber': cleanPn,
      'description': description.trim(),
      'compatibleModels': compatibleModels,
      'minStock': minStock,
      'maxStock': maxStock,
      'safeTimeDays': 60,
      'timesTouchedMin': 0,
      'timesTouchedMax': 0,
    });

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

  /// Importación masiva de Catálogo Maestro (P/N verificados) desde Excel
  Future<int> importCatalogPartsFromExcel(List<Part> importedParts) async {
    if (_currentUser.role == UserRole.technician) {
      throw Exception('Permiso denegado: Los técnicos no pueden importar catálogo.');
    }

    WriteBatch batch = _db.batch();
    int opCount = 0;

    for (var item in importedParts) {
      final cleanPn = item.partNumber.trim().toUpperCase();
      if (cleanPn.isEmpty) continue;

      final docId = cleanPn.replaceAll('/', '_');
      final docRef = _db.collection('parts').doc(docId);

      final existingIndex = _parts.indexWhere((p) => p.partNumber.toUpperCase() == cleanPn);

      if (existingIndex != -1) {
        // Reemplazamos compatibleModels por los limpios del Excel sin tocar min/max stock
        batch.set(
          docRef,
          {
            'partNumber': cleanPn,
            if (item.description.isNotEmpty) 'description': item.description,
            'compatibleModels': item.compatibleModels,
          },
          SetOptions(merge: true),
        );
      } else {
        batch.set(
          docRef,
          {
            'partNumber': cleanPn,
            'description': item.description,
            'compatibleModels': item.compatibleModels,
            'minStock': 0,
            'maxStock': 0,
            'safeTimeDays': 60,
            'timesTouchedMin': 0,
            'timesTouchedMax': 0,
          },
          SetOptions(merge: true),
        );
      }

      opCount++;
      if (opCount >= 400) {
        await batch.commit();
        batch = _db.batch();
        opCount = 0;
      }
    }

    if (opCount > 0) {
      await batch.commit();
    }

    return importedParts.length;
  }

  // --- 2. INGRESO DE STOCK EN CAJÓN ---
  Future<void> saveStock({
    required String partId,
    required int drawerNumber,
    required int quantity,
    String? userName,
  }) async {
    final part = _parts.firstWhere((p) => p.id == partId);
    final drawerRef = _db.collection('drawers').doc('drawer_$drawerNumber');
    final partRef = _db.collection('parts').doc(part.id);

    await _db.runTransaction((transaction) async {
      final drawerSnap = await transaction.get(drawerRef);
      final contents = Map<String, dynamic>.from(drawerSnap.data()?['contents'] ?? {});
      final currentQty = (contents[part.id] as num?)?.toInt() ?? 0;
      contents[part.id] = currentQty + quantity;

      transaction.set(drawerRef, {
        'drawerNumber': drawerNumber,
        'contents': contents,
      }, SetOptions(merge: true));

      final newTotal = getTotalStockForPart(part.id) + quantity;
      if (part.maxStock > 0 && newTotal >= part.maxStock) {
        transaction.update(partRef, {'timesTouchedMax': FieldValue.increment(1)});
      }

      final movRef = _db.collection('movements').doc();
      transaction.set(movRef, {
        'partNumber': part.partNumber,
        'drawerNumber': drawerNumber,
        'quantity': quantity,
        'type': MovementType.ingreso.name,
        'userName': userName ?? _currentUser.name,
        'timestamp': FieldValue.serverTimestamp(),
      });
    });
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

  // --- 3. RETIRO DE STOCK EN CAJÓN ---
  bool withdrawStock({
    required String partId,
    required int drawerNumber,
    required int quantity,
    String? userName,
  }) {
    final part = _parts.firstWhere((p) => p.id == partId);
    final currentQty = _drawers[drawerNumber]?[partId] ?? 0;

    if (currentQty < quantity) return false;

    final drawerRef = _db.collection('drawers').doc('drawer_$drawerNumber');
    final partRef = _db.collection('parts').doc(part.id);

    _db.runTransaction((transaction) async {
      final drawerSnap = await transaction.get(drawerRef);
      final contents = Map<String, dynamic>.from(drawerSnap.data()?['contents'] ?? {});
      final serverQty = (contents[part.id] as num?)?.toInt() ?? 0;

      if (serverQty < quantity) {
        throw Exception('Stock insuficiente en el servidor.');
      }

      final updatedQty = serverQty - quantity;
      if (updatedQty == 0) {
        contents.remove(part.id);
      } else {
        contents[part.id] = updatedQty;
      }

      transaction.set(drawerRef, {
        'drawerNumber': drawerNumber,
        'contents': contents,
      }, SetOptions(merge: true));

      final newTotal = getTotalStockForPart(part.id) - quantity;
      if (part.minStock > 0 && newTotal < part.minStock) {
        transaction.update(partRef, {'timesTouchedMin': FieldValue.increment(1)});
      }

      final movRef = _db.collection('movements').doc();
      transaction.set(movRef, {
        'partNumber': part.partNumber,
        'drawerNumber': drawerNumber,
        'quantity': quantity,
        'type': MovementType.retiro.name,
        'userName': userName ?? _currentUser.name,
        'timestamp': FieldValue.serverTimestamp(),
      });
    });

    return true;
  }

  // --- 4. TRANSFERENCIA ENTRE MÁQUINAS ---
  Future<void> registerTransfer({
    required String partNumber,
    required String sourceMachine,
    required String targetMachine,
    required int quantity,
  }) async {
    await _db.collection('movements').add({
      'partNumber': partNumber.trim().toUpperCase(),
      'drawerNumber': 0,
      'quantity': quantity,
      'type': MovementType.transferencia.name,
      'userName': _currentUser.name,
      'timestamp': FieldValue.serverTimestamp(),
      'sourceMachine': sourceMachine.trim(),
      'targetMachine': targetMachine.trim(),
    });
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

  Future<void> updatePartMinStock(String partId, int newMin) async {
    if (_currentUser.role == UserRole.technician) {
      throw Exception('Permiso denegado: Los técnicos no pueden editar el stock mínimo.');
    }
    final index = _parts.indexWhere((p) => p.id == partId);
    if (index != -1) {
      final newMax = ((newMin + 1) + (newMin * 0.5)).ceil();
      _parts[index].minStock = newMin;
      _parts[index].maxStock = newMax;
      notifyListeners();

      await _db.collection('parts').doc(partId).update({
        'minStock': newMin,
        'maxStock': newMax,
        'safeTimeDays': _parts[index].safeTimeDays,
      });
    }
  }

  // --- CARGA EN LOTE DE STOCK NUEVOS (EXCEL TANGO) ---
  Future<void> loadNewStockItems(List<NewStockItem> items) async {
    if (_currentUser.role == UserRole.technician) {
      throw Exception('Permiso denegado.');
    }

    final existing = await _db.collection('new_stock').get();
    WriteBatch batch = _db.batch();
    int opCount = 0;

    for (var doc in existing.docs) {
      batch.delete(doc.reference);
      opCount++;
      if (opCount >= 400) {
        await batch.commit();
        batch = _db.batch();
        opCount = 0;
      }
    }

    for (var item in items) {
      final docId = item.partNumber.replaceAll('/', '_').trim().toUpperCase();
      if (docId.isEmpty) continue;
      batch.set(_db.collection('new_stock').doc(docId), {
        'partNumber': item.partNumber.trim().toUpperCase(),
        'description': item.description,
        'unit': item.unit,
        'currentStock': item.currentStock,
        'family': item.family,
        'brand': item.brand,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      opCount++;
      if (opCount >= 400) {
        await batch.commit();
        batch = _db.batch();
        opCount = 0;
      }
    }

    if (opCount > 0) {
      await batch.commit();
    }
  }
}