import 'package:flutter/material.dart' hide Drawer;
import '../models/drawer.dart';
import '../models/part.dart';
import '../services/firestore_stock_service.dart';
import 'barcode_scanner_dialog.dart';

class WithdrawStockSheet extends StatefulWidget {
  final FirestoreStockService stockService;
  final String currentUser;

  const WithdrawStockSheet({
    super.key,
    required this.stockService,
    required this.currentUser,
  });

  @override
  State<WithdrawStockSheet> createState() => _WithdrawStockSheetState();
}

class _WithdrawStockSheetState extends State<WithdrawStockSheet> {
  final TextEditingController _searchController = TextEditingController();
  Part? _selectedPart;
  Drawer? _selectedDrawer;
  int _availableInSelectedDrawer = 0;
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
      MaterialPageRoute(builder: (_) => const BarcodeScannerDialog(title: '1/2 Escanear Part Number A Retirar')),
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
      final availableMap = widget.stockService.getAvailableDrawersForWithdrawal(found.id);
      if (availableMap.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('La pieza ${found.partNumber} no tiene stock en ningún cajón.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se encontró repuesto con código "$query"'),
          backgroundColor: Colors.orange,
        ),
      );
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
    if (numMatch != null && _selectedPart != null) {
      final drawerNum = int.tryParse(numMatch.group(0)!);
      final availableDrawers = widget.stockService.getAvailableDrawersForWithdrawal(_selectedPart!.id);

      if (drawerNum != null && availableDrawers.containsKey(drawerNum)) {
        setState(() {
          _selectedDrawer = Drawer(number: drawerNum);
          _availableInSelectedDrawer = availableDrawers[drawerNum]!;
          _quantity = 1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Cajón $drawerNum escaneado ($_availableInSelectedDrawer ud. disponibles).'),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }
    }

    _simulateDrawerFailedScan();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('El cajón "$code" no posee stock registrado de esta pieza.'),
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

  void _confirmWithdraw() {
    if (_selectedPart == null || _selectedDrawer == null || _quantity <= 0) return;

    final success = widget.stockService.withdrawStock(
      partId: _selectedPart!.id,
      drawerNumber: _selectedDrawer!.number,
      quantity: _quantity,
      userName: widget.currentUser,
    );

    if (success) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Retirado: $_quantity ud. de ${_selectedPart!.partNumber} del Cajón ${_selectedDrawer!.number}'),
          backgroundColor: Colors.deepOrange,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: No se puede retirar más de lo disponible.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableDrawers = _selectedPart != null
        ? widget.stockService.getAvailableDrawersForWithdrawal(_selectedPart!.id)
        : <int, int>{};

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
                    Icon(Icons.unarchive, color: Colors.deepOrange, size: 28),
                    SizedBox(width: 8),
                    Text('RETIRAR PIEZA', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                            : 'Paso 1: Escanea el Part Number. Fallos: $_pnScanAttempts/3.',
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
                  backgroundColor: Colors.deepOrange,
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
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
                  onPressed: () => _processPnCode(_searchController.text),
                  icon: const Icon(Icons.search),
                  label: const Text('Buscar Pieza a Retirar'),
                ),
              ],
            ],

            // PASO 2: CAJÓN OBLIGATORIO
            if (_showDrawerSelection && _selectedPart != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.deepOrange.shade200),
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

              // LA LISTA DE CAJONES SOLO APARECE SI SE ESCANEÓ O SI YA HUBO 3 FALLOS
              if (_canManualDrawerInput || _selectedDrawer != null) ...[
                const SizedBox(height: 14),
                const Text('Seleccionar manualmente:', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 6),
                Column(
                  children: availableDrawers.entries.map((entry) {
                    final drawer = Drawer(number: entry.key);
                    final availableQty = entry.value;
                    final isSelected = _selectedDrawer?.number == drawer.number;

                    return Card(
                      color: isSelected ? Colors.deepOrange.shade100 : Colors.white,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isSelected ? Colors.deepOrange : Colors.grey.shade300,
                          foregroundColor: isSelected ? Colors.white : Colors.black,
                          child: Text('${drawer.number}'),
                        ),
                        title: Text('Cajón ${drawer.number}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Disponible: $availableQty unidades'),
                        onTap: () {
                          setState(() {
                            _selectedDrawer = drawer;
                            _availableInSelectedDrawer = availableQty;
                            _quantity = 1;
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ],

              if (_selectedDrawer != null) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Cantidad a retirar:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
                          onPressed: _quantity < _availableInSelectedDrawer ? () => setState(() => _quantity++) : null,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    )
                  ],
                ),
                Text('Máximo en este cajón: $_availableInSelectedDrawer', textAlign: TextAlign.end, style: const TextStyle(color: Colors.grey, fontSize: 12)),

                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: _quantity <= _availableInSelectedDrawer ? _confirmWithdraw : null,
                  child: const Text('CONFIRMAR RETIRO', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}