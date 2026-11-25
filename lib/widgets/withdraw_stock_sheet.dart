import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/part.dart';
import '../services/firestore_stock_service.dart';

class WithdrawStockSheet extends StatefulWidget {
  final FirestoreStockService stockService;

  const WithdrawStockSheet({super.key, required this.stockService});

  @override
  State<WithdrawStockSheet> createState() => _WithdrawStockSheetState();
}

class _WithdrawStockSheetState extends State<WithdrawStockSheet> {
  final _partCodeController = TextEditingController();

  Part? _selectedPart;
  int? _selectedDrawer;
  int _quantity = 1;

  @override
  void dispose() {
    _partCodeController.dispose();
    super.dispose();
  }

  /// Abre el escáner de cámara con ciclo de vida controlado para evitar bloqueos en iOS Safari
  Future<String?> _scanBarcodeWithDialog({required String title}) async {
    final controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
    );
    bool hasScanned = false;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 300,
            height: 280,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: MobileScanner(
                controller: controller,
                onDetect: (capture) {
                  if (hasScanned) return;
                  final barcodes = capture.barcodes;
                  if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                    hasScanned = true;
                    final code = barcodes.first.rawValue!.trim();
                    Navigator.of(dialogContext).pop(code);
                  }
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );

    await controller.dispose();
    return result;
  }

  Future<void> _scanPartStep() async {
    final code = await _scanBarcodeWithDialog(title: '1. Escanear Pieza a Retirar');
    if (code != null && code.isNotEmpty) {
      _partCodeController.text = code;
      _searchPart(code);
    }
  }

  void _searchPart(String code) {
    final found = widget.stockService.findPartByCode(code);
    setState(() {
      _selectedPart = found;
      _selectedDrawer = null;
      _quantity = 1;
    });

    if (found == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('El Part Number "$code" no figura en el catálogo.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _scanDrawerStep() async {
    if (_selectedPart == null) return;
    final code = await _scanBarcodeWithDialog(title: '2. Escanear Cajón de Origen');
    if (code != null && code.isNotEmpty) {
      final digits = RegExp(r'\d+').firstMatch(code)?.group(0);
      final drawerNum = digits != null ? int.tryParse(digits) : null;
      final availableMap = widget.stockService.getAvailableDrawersForWithdrawal(_selectedPart!.id);

      if (drawerNum != null && availableMap.containsKey(drawerNum)) {
        setState(() {
          _selectedDrawer = drawerNum;
          _quantity = 1;
        });
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No hay stock de ${_selectedPart!.partNumber} en el cajón "$code".'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _confirmWithdrawal() {
    if (_selectedPart == null || _selectedDrawer == null) return;

    final success = widget.stockService.withdrawStock(
      partId: _selectedPart!.id,
      drawerNumber: _selectedDrawer!,
      quantity: _quantity,
    );

    if (success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Retiradas $_quantity unid. de ${_selectedPart!.partNumber} del Cajón #$_selectedDrawer'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stock insuficiente en el cajón seleccionado.'),
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

    final maxAvailable = (_selectedDrawer != null) ? (availableDrawers[_selectedDrawer!] ?? 0) : 0;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Retirar Repuesto de Cajón',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // PASO 1: IDENTIFICAR PIEZA
            const Text('Paso 1: Identificar Repuesto',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _partCodeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Part Number',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: _searchPart,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: () => _searchPart(_partCodeController.text),
                  icon: const Icon(Icons.search),
                  tooltip: 'Buscar P/N',
                ),
                const SizedBox(width: 6),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onPressed: _scanPartStep,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Escanear Pieza'),
                ),
              ],
            ),

            // PAUSA DE CONFIRMACIÓN ENTRE ESCANEO DE PIEZA Y ESCANEO DE CAJÓN
            if (_selectedPart != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade400),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pieza: ${_selectedPart!.partNumber} — ${_selectedPart!.description}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      availableDrawers.isEmpty
                          ? 'Sin stock físico disponible en cajones.'
                          : 'Disponible en: ${availableDrawers.entries.map((e) => 'Cajón #${e.key} (${e.value} u.)').join(', ')}',
                      style: TextStyle(
                        fontSize: 13,
                        color: availableDrawers.isEmpty ? Colors.red : Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (availableDrawers.isNotEmpty) ...[
                      const Divider(height: 20),
                      const Text(
                        'Paso 2: ¿Deseas comenzar el escaneo del cajón?',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: _scanDrawerStep,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: Text(_selectedDrawer == null
                              ? 'COMENZAR ESCANEO DE CAJÓN'
                              : 'VOLVER A ESCANEAR CAJÓN (#$_selectedDrawer)'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        value: _selectedDrawer,
                        decoration: const InputDecoration(
                          labelText: 'O seleccionar Cajón manualmente',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: availableDrawers.entries
                            .map((e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text('Cajón #${e.key} (Disp: ${e.value})'),
                                ))
                            .toList(),
                        onChanged: (val) => setState(() {
                          _selectedDrawer = val;
                          _quantity = 1;
                        }),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            // PASO 3: CANTIDAD Y RETIRO
            if (_selectedPart != null && _selectedDrawer != null && maxAvailable > 0) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Cantidad a retirar (Máx: $maxAvailable):',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Row(
                    children: [
                      IconButton(
                        onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('$_quantity',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(
                        onPressed: _quantity < maxAvailable ? () => setState(() => _quantity++) : null,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _confirmWithdrawal,
                  icon: const Icon(Icons.outbox),
                  label: const Text('CONFIRMAR RETIRO'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}