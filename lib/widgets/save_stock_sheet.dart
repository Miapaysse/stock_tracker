import 'package:flutter/material.dart' hide Drawer;
import '../models/drawer.dart';
import '../models/part.dart';
import '../models/user_role.dart';
import '../services/firestore_stock_service.dart';
import 'barcode_scanner_dialog.dart';

class SaveStockSheet extends StatefulWidget {
  final FirestoreStockService stockService;
  final String currentUser;

  const SaveStockSheet({
    super.key,
    required this.stockService,
    required this.currentUser,
  });

  @override
  State<SaveStockSheet> createState() => _SaveStockSheetState();
}

class _SaveStockSheetState extends State<SaveStockSheet> {
  final TextEditingController _searchController = TextEditingController();
  Part? _selectedPart;
  Drawer? _selectedDrawer;
  int _quantity = 1;
  bool _showDrawerSelection = false;

  int _pnScanAttempts = 0;
  bool get _canManualPnInput => _pnScanAttempts >= 3;

  int _drawerScanAttempts = 0;
  bool get _canManualDrawerInput => _drawerScanAttempts >= 3;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openPnScanner() async {
    final scannedCode = await Navigator.push<String?>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerDialog(title: '1/2 Escanear Part Number')),
    );

    if (scannedCode != null && scannedCode.isNotEmpty) {
      _processPnCode(scannedCode);
    } else {
      _simulatePnFailedScan();
    }
  }

  void _processPnCode(String code) {
    final query = code.trim();
    if (query.isEmpty) return;

    final found = widget.stockService.findPartByCode(query);
    if (found != null) {
      setState(() {
        _selectedPart = found;
        _showDrawerSelection = true;
        _selectedDrawer = null;
        _drawerScanAttempts = 0;
      });

      // DISPARA AUTOMÁTICAMENTE EL ESCÁNER DE CAJÓN AL DETECTAR EL REPUESTO
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openDrawerScanner();
      });
    } else {
      if (widget.stockService.currentUser.role == UserRole.technician) {
        _showTechnicianWarningDialog(query);
      } else {
        _showAddPartDialog(query);
      }
    }
  }

  Future<void> _openDrawerScanner() async {
    final scannedCode = await Navigator.push<String?>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerDialog(title: '2/2 Escanear Etiqueta de Cajón')),
    );

    if (scannedCode != null && scannedCode.isNotEmpty) {
      _processDrawerCode(scannedCode);
    } else {
      _simulateDrawerFailedScan();
    }
  }

  void _processDrawerCode(String code) {
    final numMatch = RegExp(r'\d+').firstMatch(code);
    if (numMatch != null) {
      final drawerNum = int.tryParse(numMatch.group(0)!);
      if (drawerNum != null && drawerNum >= 1 && drawerNum <= 20) {
        setState(() {
          _selectedDrawer = Drawer(number: drawerNum);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Cajón $drawerNum escaneado correctamente.'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
    }

    _simulateDrawerFailedScan();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('El código "$code" no corresponde a un cajón válido (1 a 20).'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _simulatePnFailedScan() {
    setState(() => _pnScanAttempts++);
  }

  void _simulateDrawerFailedScan() {
    setState(() => _drawerScanAttempts++);
  }

  void _showTechnicianWarningDialog(String code) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 8),
              Text('Part Number No Registrado'),
            ],
          ),
          content: Text('El Part Number "$code" no existe en el catálogo.\n\nComo Técnico no puedes agregar repuestos. Solicita el alta a Gabriel o Facu.'),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Entendido'),
            ),
          ],
        );
      },
    );
  }

  void _showAddPartDialog(String initialCode) {
    final partNumberController = TextEditingController(text: initialCode);
    final modelController = TextEditingController();
    final descriptionController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.add_box, color: Colors.blueAccent),
              SizedBox(width: 8),
              Text('Alta en Catálogo (Admin)'),
            ],
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: partNumberController,
                    decoration: const InputDecoration(labelText: '1. Part Number *', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: modelController,
                    decoration: const InputDecoration(labelText: '2. Modelo de impresora *', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: '3. Descripción *', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  final newPart = widget.stockService.addPart(
                    partNumber: partNumberController.text,
                    compatibleModels: [modelController.text.trim()],
                    description: descriptionController.text,
                  );
                  Navigator.pop(dialogContext);
                  setState(() {
                    _selectedPart = newPart;
                    _showDrawerSelection = true;
                    _selectedDrawer = null;
                    _drawerScanAttempts = 0;
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _openDrawerScanner();
                  });
                }
              },
              child: const Text('Guardar y Pasar a Cajón'),
            ),
          ],
        );
      },
    );
  }

  void _confirmSave() {
    if (_selectedPart == null || _selectedDrawer == null || _quantity <= 0) return;

    widget.stockService.addStock(
      partId: _selectedPart!.id,
      drawerNumber: _selectedDrawer!.number,
      quantity: _quantity,
      userName: widget.currentUser,
    );

    Navigator.pop(context, true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✓ Guardado: $_quantity ud. de ${_selectedPart!.partNumber} en Cajón ${_selectedDrawer!.number}'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final drawerNumbers = widget.stockService.getDrawersForSaving();
    final stockPerDrawer = _selectedPart != null
        ? widget.stockService.getStockPerDrawerForPart(_selectedPart!.id)
        : <int, int>{};
    final drawersWithStock = drawerNumbers
        .where((number) => (stockPerDrawer[number] ?? 0) > 0)
        .map((number) => Drawer(number: number))
        .toList();
    final otherDrawers = drawerNumbers
        .where((number) => (stockPerDrawer[number] ?? 0) == 0)
        .map((number) => Drawer(number: number))
        .toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        top: 20,
        left: 16,
        right: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.archive, color: Colors.green, size: 28),
                    SizedBox(width: 8),
                    Text('GUARDAR PIEZA', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(),
            const SizedBox(height: 10),

            // PASO 1: PART NUMBER
            if (!_showDrawerSelection) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _canManualPnInput ? Colors.blue.shade50 : Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _canManualPnInput ? Colors.blue : Colors.amber),
                ),
                child: Row(
                  children: [
                    Icon(_canManualPnInput ? Icons.lock_open : Icons.qr_code_scanner, 
                         color: _canManualPnInput ? Colors.blue : Colors.amber.shade900),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _canManualPnInput
                            ? '✓ Teclado manual habilitado para Part Number.'
                            : 'Paso 1: Escanea el Part Number del repuesto. Fallos: $_pnScanAttempts/3.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _canManualPnInput ? Colors.blue.shade900 : Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _openPnScanner,
                icon: const Icon(Icons.camera_alt),
                label: const Text('ESCANEAR PART NUMBER', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),

              if (!_canManualPnInput)
                OutlinedButton.icon(
                  onPressed: _simulatePnFailedScan,
                  icon: const Icon(Icons.warning_amber, color: Colors.orange),
                  label: Text('Simular Fallo Escaneo PN ($_pnScanAttempts/3)', style: const TextStyle(color: Colors.orange)),
                ),

              if (_canManualPnInput) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Ingreso Manual: Part Number',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: _processPnCode,
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  onPressed: () => _processPnCode(_searchController.text),
                  icon: const Icon(Icons.search),
                  label: const Text('Buscar Manualmente'),
                ),
              ],
            ],

            // PASO 2: CAJÓN OBLIGATORIO
            if (_showDrawerSelection && _selectedPart != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('PN: ${_selectedPart!.partNumber}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text(_selectedPart!.description),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _showDrawerSelection = false;
                        _selectedPart = null;
                      }),
                      child: const Text('Cambiar PN'),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _selectedDrawer != null
                      ? Colors.green.shade50
                      : (_canManualDrawerInput ? Colors.blue.shade50 : Colors.amber.shade50),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _selectedDrawer != null
                        ? Colors.green
                        : (_canManualDrawerInput ? Colors.blue : Colors.amber),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _selectedDrawer != null
                          ? Icons.check_circle
                          : (_canManualDrawerInput ? Icons.lock_open : Icons.qr_code),
                      color: _selectedDrawer != null
                          ? Colors.green.shade800
                          : (_canManualDrawerInput ? Colors.blue : Colors.amber.shade900),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _selectedDrawer != null
                            ? '✓ Cajón ${_selectedDrawer!.number} asignado por escaneo.'
                            : (_canManualDrawerInput
                                ? '✓ Selección manual de cajón habilitada (3/3 fallos).'
                                : 'Paso 2: Debes escanear el código del cajón. Fallos: $_drawerScanAttempts/3.'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _selectedDrawer != null
                              ? Colors.green.shade900
                              : (_canManualDrawerInput ? Colors.blue.shade900 : Colors.amber.shade900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _openDrawerScanner,
                icon: const Icon(Icons.qr_code_2),
                label: Text(
                  _selectedDrawer != null
                      ? 'RE-ESCANEAR OTRO CAJÓN'
                      : 'ABRIR ESCÁNER DE CAJÓN',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 6),

              if (!_canManualDrawerInput && _selectedDrawer == null)
                OutlinedButton.icon(
                  onPressed: _simulateDrawerFailedScan,
                  icon: const Icon(Icons.warning_amber, color: Colors.orange),
                  label: Text('Simular Fallo Escaneo Cajón ($_drawerScanAttempts/3)', style: const TextStyle(color: Colors.orange)),
                ),

              // LA GRILLA SOLO APARECE SI SE ESCANEÓ O SI YA HUBO 3 FALLOS
              if (_canManualDrawerInput || _selectedDrawer != null) ...[
                const SizedBox(height: 14),
                if (drawersWithStock.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Sugerencia: Cajones con esta pieza', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          children: drawersWithStock.map((drawer) {
                            final isSelected = _selectedDrawer?.number == drawer.number;
                            final qty = stockPerDrawer[drawer.number] ?? 0;
                            return ChoiceChip(
                              label: Text('Cajón ${drawer.number} ($qty ud.)'),
                              selected: isSelected,
                              onSelected: (selected) => setState(() => _selectedDrawer = selected ? drawer : null),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                const Text('Seleccionar manualmente:', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 6),
                SizedBox(
                  height: 120,
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      childAspectRatio: 1.4,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                    ),
                    itemCount: otherDrawers.length,
                    itemBuilder: (context, index) {
                      final drawer = otherDrawers[index];
                      final isSelected = _selectedDrawer?.number == drawer.number;
                      return InkWell(
                        onTap: () => setState(() => _selectedDrawer = drawer),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.green : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: Text('${drawer.number}', style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black)),
                        ),
                      );
                    },
                  ),
                ),
              ],

              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Cantidad a guardar:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  Row(
                    children: [
                      IconButton.filledTonal(
                        onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                        icon: const Icon(Icons.remove),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text('$_quantity', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ),
                      IconButton.filledTonal(
                        onPressed: () => setState(() => _quantity++),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  )
                ],
              ),

              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: _selectedDrawer != null ? _confirmSave : null,
                child: const Text('CONFIRMAR GUARDADO', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}