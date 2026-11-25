import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/part.dart';
import '../services/firestore_stock_service.dart';

class SaveStockSheet extends StatefulWidget {
  final FirestoreStockService stockService;

  const SaveStockSheet({super.key, required this.stockService});

  @override
  State<SaveStockSheet> createState() => _SaveStockSheetState();
}

class _SaveStockSheetState extends State<SaveStockSheet> {
  final _partCodeController = TextEditingController();
  final _drawerCodeController = TextEditingController();

  Part? _selectedPart;
  int? _selectedDrawer;
  int _quantity = 1;
  bool _isSaving = false;

  @override
  void dispose() {
    _partCodeController.dispose();
    _drawerCodeController.dispose();
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
    final code = await _scanBarcodeWithDialog(title: '1. Escanear Código de Pieza');
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
      _drawerCodeController.clear();
    });

    if (found == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('El Part Number "$code" no figura en el catálogo verificado.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _scanDrawerStep() async {
    final code = await _scanBarcodeWithDialog(title: '2. Escanear Código de Cajón');
    if (code != null && code.isNotEmpty) {
      _drawerCodeController.text = code;
      _parseDrawerCode(code);
    }
  }

  void _parseDrawerCode(String code) {
    final digits = RegExp(r'\d+').firstMatch(code)?.group(0);
    final drawerNum = digits != null ? int.tryParse(digits) : null;

    if (drawerNum != null && drawerNum >= 1 && drawerNum <= 20) {
      setState(() => _selectedDrawer = drawerNum);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Código de cajón inválido ("$code"). Debe ser entre 1 y 20.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _confirmSave() async {
    if (_selectedPart == null || _selectedDrawer == null) return;
    setState(() => _isSaving = true);

    try {
      await widget.stockService.saveStock(
        partId: _selectedPart!.id,
        drawerNumber: _selectedDrawer!,
        quantity: _quantity,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Se ingresaron $_quantity unid. de ${_selectedPart!.partNumber} en Cajón #$_selectedDrawer'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableDrawers = widget.stockService.getDrawersForSaving();

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
            const Text('Guardar Repuesto en Cajón',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // PASO 1: ESCANEAR O INGRESAR PIEZA
            const Text('Paso 1: Identificar Repuesto',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
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
                    backgroundColor: Colors.blueAccent,
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
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade400),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Pieza verificada: ${_selectedPart!.partNumber}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(_selectedPart!.description),
                    if (_selectedPart!.compatibleModels.isNotEmpty)
                      Text(
                        'Modelos: ${_selectedPart!.compatibleModels.join(', ')}',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
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
                      items: availableDrawers
                          .map((d) => DropdownMenuItem(value: d, child: Text('Cajón #$d')))
                          .toList(),
                      onChanged: (val) => setState(() => _selectedDrawer = val),
                    ),
                  ],
                ),
              ),
            ],

            // PASO 3: CANTIDAD Y GUARDADO
            if (_selectedPart != null && _selectedDrawer != null) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Cantidad a ingresar:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Row(
                    children: [
                      IconButton(
                        onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('$_quantity',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(
                        onPressed: () => setState(() => _quantity++),
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
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _isSaving ? null : _confirmSave,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_isSaving ? 'GUARDANDO...' : 'CONFIRMAR INGRESO'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}