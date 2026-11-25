import 'package:flutter/material.dart';
import 'package:stock_tracker/services/firestore_stock_service.dart';
import '../models/user_role.dart';
import '../models/movement.dart';
import 'stock_query_screen.dart';
import 'alerts_and_history_screen.dart';
import 'admin_panel_screen.dart';
import '../widgets/save_stock_sheet.dart';
import '../widgets/withdraw_stock_sheet.dart';
import '../widgets/barcode_scanner_dialog.dart';

class HomeScreen extends StatefulWidget {
  final FirestoreStockService stockService;

  const HomeScreen({super.key, required this.stockService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  void _openSaveSheet() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SaveStockSheet(
        stockService: widget.stockService,
      ),
    );
    if (result == true) setState(() {});
  }

  void _openWithdrawSheet() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => WithdrawStockSheet(
        stockService: widget.stockService,
      ),
    );
    if (result == true) setState(() {});
  }

  void _openTransferDialog() {
    final pnController = TextEditingController();
    final sourceController = TextEditingController();
    final targetController = TextEditingController();
    int qty = 1;

    Future<void> scanIntoField(TextEditingController controller, String title) async {
      final code = await Navigator.push<String?>(
        context,
        MaterialPageRoute(builder: (_) => BarcodeScannerDialog(title: title)),
      );
      if (code != null && code.isNotEmpty) {
        controller.text = code;
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.swap_horiz, color: Colors.purple),
                  SizedBox(width: 8),
                  Text('Transferencia entre Máquinas'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Usa el icono de cámara para escanear los códigos de barras de repuesto y máquinas.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 14),

                    // CAMPO 1: Part Number Repuesto + Escáner
                    TextField(
                      controller: pnController,
                      decoration: InputDecoration(
                        labelText: 'Part Number del Repuesto *',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.qr_code_scanner, color: Colors.purple),
                          onPressed: () async {
                            await scanIntoField(pnController, 'Escanear Part Number Repuesto');
                            setDialogState(() {});
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // CAMPO 2: Serial Number Origen + Escáner
                    TextField(
                      controller: sourceController,
                      decoration: InputDecoration(
                        labelText: 'Serial Number Máquina Origen *',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.qr_code_scanner, color: Colors.purple),
                          onPressed: () async {
                            await scanIntoField(sourceController, 'Escanear Serial Máquina Origen');
                            setDialogState(() {});
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // CAMPO 3: Serial Number Destino + Escáner
                    TextField(
                      controller: targetController,
                      decoration: InputDecoration(
                        labelText: 'Serial Number Máquina Destino *',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.qr_code_scanner, color: Colors.purple),
                          onPressed: () async {
                            await scanIntoField(targetController, 'Escanear Serial Máquina Destino');
                            setDialogState(() {});
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Cantidad:', style: TextStyle(fontWeight: FontWeight.w600)),
                        Row(
                          children: [
                            IconButton.filledTonal(
                              icon: const Icon(Icons.remove),
                              onPressed: qty > 1 ? () => setDialogState(() => qty--) : null,
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text('$qty', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            ),
                            IconButton.filledTonal(
                              icon: const Icon(Icons.add),
                              onPressed: () => setDialogState(() => qty++),
                            ),
                          ],
                        )
                      ],
                    )
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
                  onPressed: () async {
                    if (pnController.text.trim().isNotEmpty &&
                        sourceController.text.trim().isNotEmpty &&
                        targetController.text.trim().isNotEmpty) {
                      try {
                        await widget.stockService.registerTransfer(
                          partNumber: pnController.text.trim(),
                          sourceMachine: sourceController.text.trim(),
                          targetMachine: targetController.text.trim(),
                          quantity: qty,
                        );
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✓ Transferencia registrada correctamente.'),
                            backgroundColor: Colors.purple,
                          ),
                        );
                      } catch (error) {
                        if (!dialogContext.mounted) return;
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(
                            content: Text('No se pudo registrar la transferencia: $error'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Registrar Transferencia'),
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
              _buildDetailRow('Tipo:', m.type.name.toUpperCase()),
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
    final user = widget.stockService.currentUser;
    final isAdminOrAdvanced = user.role == UserRole.admin || user.role == UserRole.advancedAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Control de Stock'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<AppUser>(
                value: user,
                dropdownColor: Colors.blue.shade900,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                items: widget.stockService.users.map((u) {
                  return DropdownMenuItem<AppUser>(
                    value: u,
                    child: Text('${u.name} (${u.roleDisplayName})'),
                  );
                }).toList(),
                onChanged: (newUser) {
                  if (newUser != null) {
                    setState(() {
                      widget.stockService.setCurrentUser(newUser);
                    });
                  }
                },
              ),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.stockService,
        builder: (context, _) {
          return IndexedStack(
            index: _currentIndex,
            children: [
              _buildOperationsTab(),
              StockQueryScreen(stockService: widget.stockService),
              AlertsAndHistoryScreen(stockService: widget.stockService),
              if (isAdminOrAdvanced)
                AdminPanelScreen(stockService: widget.stockService)
              else
                const Center(child: Text('Acceso restringido para Administradores.')),
            ],
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          if (index == 3 && !isAdminOrAdvanced) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⚠️ Solo los Administradores (Gabriel / Facu) pueden entrar aquí.'),
                backgroundColor: Colors.orange,
              ),
            );
            return;
          }
          setState(() {
            _currentIndex = index;
          });
        },
        items: [
          const BottomNavigationBarView(icon: Icon(Icons.touch_app), label: 'Operaciones'),
          const BottomNavigationBarView(icon: Icon(Icons.grid_view), label: 'Navegar Stock'),
          const BottomNavigationBarView(icon: Icon(Icons.warning_amber_rounded), label: 'Stock Bajo'),
          BottomNavigationBarView(
            icon: Icon(Icons.admin_panel_settings, color: isAdminOrAdvanced ? Colors.purple : Colors.grey),
            label: 'Administración',
          ),
        ],
      ),
    );
  }

  Widget _buildOperationsTab() {
    final movements = widget.stockService.movements.reversed.take(5).toList();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.badge, color: Colors.blueAccent),
                const SizedBox(width: 10),
                Text(
                  'Operador Activo: ${widget.stockService.currentUser.name}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: _openSaveSheet,
            icon: const Icon(Icons.archive),
            label: const Text('GUARDAR PIEZA', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: _openWithdrawSheet,
            icon: const Icon(Icons.unarchive),
            label: const Text('RETIRAR PIEZA', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),

          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: Colors.purple, width: 2),
              foregroundColor: Colors.purple,
            ),
            onPressed: _openTransferDialog,
            icon: const Icon(Icons.swap_horiz),
            label: const Text('TRANSFERIR ENTRE MÁQUINAS', 
                             style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ),

          const SizedBox(height: 24),
          const Text('Últimos movimientos:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),

          Expanded(
            child: movements.isEmpty
                ? const Center(child: Text('No hay movimientos recientes.', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: movements.length,
                    itemBuilder: (context, index) {
                      final m = movements[index];
                      final isSave = m.type == MovementType.ingreso;
                      final isTransfer = m.type == MovementType.transferencia;

                      return Card(
                        child: ListTile(
                          onTap: () => _showMovementDetailDialog(m),
                          leading: CircleAvatar(
                            backgroundColor: isTransfer
                                ? Colors.purple.shade50
                                : (isSave ? Colors.green.shade50 : Colors.deepOrange.shade50),
                            child: Icon(
                              isTransfer
                                  ? Icons.swap_horiz
                                  : (isSave ? Icons.arrow_downward : Icons.arrow_upward),
                              color: isTransfer
                                  ? Colors.purple
                                  : (isSave ? Colors.green : Colors.deepOrange),
                            ),
                          ),
                          title: Text('${m.partNumber} (${m.quantity} ud.)'),
                          subtitle: Text(
                            isTransfer
                                ? 'Serial Origen: ${m.sourceMachine} ➔ Serial Destino: ${m.targetMachine}'
                                : 'Cajón ${m.drawerNumber} • Por: ${m.userName}',
                          ),
                          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class BottomNavigationBarView extends BottomNavigationBarItem {
  const BottomNavigationBarView({required super.icon, required super.label});
}