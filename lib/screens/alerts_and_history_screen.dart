import 'package:flutter/material.dart' hide Drawer;
import '../models/part.dart';
import '../models/movement.dart';
import '../models/user_role.dart';
import '../services/firestore_stock_service.dart';

class AlertsAndHistoryScreen extends StatefulWidget {
  final FirestoreStockService stockService;

  const AlertsAndHistoryScreen({super.key, required this.stockService});

  @override
  State<AlertsAndHistoryScreen> createState() => _AlertsAndHistoryScreenState();
}

class _AlertsAndHistoryScreenState extends State<AlertsAndHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _filterQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Dialog para que el Administrador defina todas las variables de Stock Mín, Máx, SafeTime y Periodo por Part Number
  void _showSetMinStockDialog({Part? preselectedPart}) {
    if (widget.stockService.currentUser.role == UserRole.technician) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Acceso Denegado: Los técnicos no pueden modificar los parámetros de stock.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Part? selectedPart = preselectedPart;
    final minStockController = TextEditingController(text: preselectedPart != null ? preselectedPart.minStock.toString() : '');
    final maxStockController = TextEditingController(text: preselectedPart != null ? preselectedPart.maxStock.toString() : '');
    final safeTimeController = TextEditingController(text: preselectedPart != null ? preselectedPart.safeTimeDays.toString() : '60');
    final periodDaysController = TextEditingController(text: '30');

    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.tune, color: Colors.deepOrange),
                  SizedBox(width: 8),
                  Text('Ajustar Variables de Part Number'),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<Part>(
                        value: selectedPart,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Repuesto (Part Number)', border: OutlineInputBorder()),
                        items: widget.stockService.parts.map((part) {
                          return DropdownMenuItem<Part>(
                            value: part,
                            child: Text('${part.partNumber} - ${part.description}', overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (part) {
                          setDialogState(() {
                            selectedPart = part;
                            if (part != null) {
                              minStockController.text = part.minStock.toString();
                              maxStockController.text = part.maxStock.toString();
                              safeTimeController.text = part.safeTimeDays.toString();
                            }
                          });
                        },
                        validator: (val) => val == null ? 'Selecciona un repuesto' : null,
                      ),
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: minStockController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Stock Mínimo *', border: OutlineInputBorder()),
                              validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: maxStockController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Stock Máximo *', border: OutlineInputBorder()),
                              validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: safeTimeController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Safe Time (Días)', border: OutlineInputBorder()),
                              validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: periodDaysController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Periodo (Días)', border: OutlineInputBorder()),
                              validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
                  onPressed: () {
                    if (formKey.currentState?.validate() ?? false) {
                      final newMin = int.parse(minStockController.text.trim());
                      final newMax = int.parse(maxStockController.text.trim());
                      final newSafeTime = int.parse(safeTimeController.text.trim());

                      widget.stockService.updatePartMinStock(selectedPart!.id, newMin);
                      selectedPart!.maxStock = newMax;
                      selectedPart!.safeTimeDays = newSafeTime;

                      Navigator.pop(dialogContext);
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✓ Parámetros actualizados para PN ${selectedPart!.partNumber}'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  child: const Text('Guardar Variables'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showMovementDetailDialog(Movement m) {
    final isTransfer = m.type == MovementType.transferencia;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isTransfer ? Icons.swap_horiz : Icons.receipt_long,
              color: isTransfer ? Colors.purple : Colors.blue,
            ),
            const SizedBox(width: 8),
            Text(isTransfer ? 'Detalle de Transferencia' : 'Detalle de Movimiento'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Part Number:', m.partNumber),
            _buildDetailRow('Cantidad:', '${m.quantity} unidades'),
            _buildDetailRow('Operador:', m.userName),
            _buildDetailRow('Fecha y Hora:', m.timestamp.toString().substring(0, 16)),
            const Divider(),
            if (isTransfer) ...[
              _buildDetailRow('Serial Number Origen:', m.sourceMachine ?? 'N/A', isHighlight: true),
              _buildDetailRow('Serial Number Destino:', m.targetMachine ?? 'N/A', isHighlight: true),
            ] else ...[
              _buildDetailRow('Cajón:', '${m.drawerNumber}'),
              _buildDetailRow('Tipo de Operación:', m.type.name.toUpperCase()),
            ]
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: isHighlight ? Colors.purple.shade900 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            labelColor: Colors.deepOrange,
            indicatorColor: Colors.deepOrange,
            tabs: [
              Tab(icon: Icon(Icons.warning_amber_rounded), text: 'Alertas & Estadísticas'),
              Tab(icon: Icon(Icons.history), text: 'Historial Movimientos'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildAlertsAndStatsTab(),
                _buildHistoryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsAndStatsTab() {
    final currentUser = widget.stockService.currentUser;
    final isAdmin = currentUser.role == UserRole.admin || currentUser.role == UserRole.advancedAdmin;
    final allParts = widget.stockService.parts;

    final alertParts = allParts.where((part) {
      final total = widget.stockService.getTotalStockForPart(part.id);
      final isBelowMin = total < part.minStock;

      if (_filterQuery.isEmpty) return isBelowMin;

      final q = _filterQuery.toLowerCase();
      final matchesPN = part.partNumber.toLowerCase().contains(q);
      final matchesDesc = part.description.toLowerCase().contains(q);
      final matchesModel = part.compatibleModels.any((m) => m.toLowerCase().contains(q));

      return isBelowMin && (matchesPN || matchesDesc || matchesModel);
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Filtrar Alertas (PN, Descripción o Modelo)',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _filterQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() {
                        _searchController.clear();
                        _filterQuery = '';
                      }),
                    )
                  : null,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (val) => setState(() => _filterQuery = val.trim()),
          ),
          const SizedBox(height: 12),

          if (isAdmin)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange.shade600, foregroundColor: Colors.white),
              onPressed: () => _showSetMinStockDialog(),
              icon: const Icon(Icons.tune),
              label: const Text('ESTABLECER / EDITAR VARIABLES DE PART NUMBER'),
            )
          else
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
              child: const Row(
                children: [
                  Icon(Icons.lock, color: Colors.grey, size: 20),
                  SizedBox(width: 8),
                  Text('Edición de stock mínimo reservada a Administradores.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Piezas por debajo del Mínimo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Chip(
                label: Text('${alertParts.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                backgroundColor: alertParts.isNotEmpty ? Colors.red.shade700 : Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (alertParts.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
              child: const Text('✓ No hay piezas por debajo del mínimo.', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: alertParts.length,
              itemBuilder: (context, index) {
                final part = alertParts[index];
                final currentTotal = widget.stockService.getTotalStockForPart(part.id);
                final missingQty = part.minStock - currentTotal;

                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.warning, color: Colors.red),
                    title: Text('${part.partNumber} - ${part.description}'),
                    subtitle: Text('Faltan $missingQty ud. (Actual: $currentTotal | Mín: ${part.minStock} | Máx: ${part.maxStock})'),
                    trailing: isAdmin
                        ? IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _showSetMinStockDialog(preselectedPart: part),
                          )
                        : null,
                  ),
                );
              },
            ),

          const SizedBox(height: 20),
          const Divider(),

          const Text('Artículos que más veces tocaron sus límites:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),

          ...allParts.map((p) {
            return Card(
              color: Colors.grey.shade50,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text('${p.partNumber} (${p.description})', style: const TextStyle(fontWeight: FontWeight.bold))),
                    Chip(
                      label: Text('Mín: ${p.timesTouchedMin} veces'),
                      backgroundColor: Colors.orange.shade100,
                    ),
                    const SizedBox(width: 6),
                    Chip(
                      label: Text('Máx: ${p.timesTouchedMax} veces'),
                      backgroundColor: Colors.blue.shade100,
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    final movements = widget.stockService.movements.reversed.toList();
    return ListView.builder(
      itemCount: movements.length,
      itemBuilder: (context, index) {
        final m = movements[index];
        final isTransfer = m.type == MovementType.transferencia;

        return ListTile(
          onTap: () => _showMovementDetailDialog(m),
          leading: Icon(
            isTransfer ? Icons.swap_horiz : (m.type == MovementType.ingreso ? Icons.arrow_downward : Icons.arrow_upward),
            color: isTransfer ? Colors.purple : (m.type == MovementType.ingreso ? Colors.green : Colors.deepOrange),
          ),
          title: Text('${m.type.name.toUpperCase()}: ${m.partNumber} (${m.quantity} ud.)'),
          subtitle: Text(
            isTransfer
                ? 'De Serial: ${m.sourceMachine} ➔ A Serial: ${m.targetMachine}\nUsuario: ${m.userName}'
                : 'Usuario: ${m.userName} • Fecha: ${m.timestamp.toString().substring(0, 16)}',
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        );
      },
    );
  }
}