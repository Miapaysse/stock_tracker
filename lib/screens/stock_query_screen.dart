import 'package:flutter/material.dart';
import '../models/part.dart';
import '../services/firestore_stock_service.dart';

/// Modelo auxiliar para la representación limpia de partes en un cajón
class DrawerPartItem {
  final Part part;
  final int quantity;

  DrawerPartItem({required this.part, required this.quantity});
}

class StockQueryScreen extends StatefulWidget {
  final FirestoreStockService stockService;

  const StockQueryScreen({super.key, required this.stockService});

  @override
  State<StockQueryScreen> createState() => _StockQueryScreenState();
}

class _StockQueryScreenState extends State<StockQueryScreen> {
  int _selectedMainTab = 0; // 0 = Stock Físico (Cajones), 1 = Stock Nuevos (Excel)
  int _physicalSubView = 0;  // 0 = Mapa de Cajones, 1 = Lista por Repuesto
  String _searchQuery = '';

  /// Obtiene la lista de piezas alojadas dentro de un cajón específico
  List<DrawerPartItem> _getPartsInDrawer(int drawerNumber) {
    final List<DrawerPartItem> result = [];
    final stocksInDrawer = widget.stockService.stocks.where((s) => s.drawerNumber == drawerNumber);

    for (var stock in stocksInDrawer) {
      final partList = widget.stockService.parts.where((p) => p.id == stock.partId);
      if (partList.isNotEmpty) {
        result.add(DrawerPartItem(
          part: partList.first,
          quantity: stock.quantity,
        ));
      }
    }
    return result;
  }

  /// Despliega la ventana flotante con el detalle de las piezas dentro del cajón
  void _showDrawerDetailsDialog(int drawerNumber) {
    final itemsInDrawer = _getPartsInDrawer(drawerNumber);
    final totalQty = itemsInDrawer.fold<int>(0, (sum, item) => sum + item.quantity);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: itemsInDrawer.isNotEmpty ? Colors.blue.shade100 : Colors.grey.shade200,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.inbox,
                  color: itemsInDrawer.isNotEmpty ? Colors.blue.shade800 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Cajón $drawerNumber', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  Text(
                    itemsInDrawer.isNotEmpty ? '$totalQty unidades en total' : 'Cajón vacío',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: itemsInDrawer.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        const Text('Este cajón está vacío.', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: itemsInDrawer.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = itemsInDrawer[index];

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          child: Icon(Icons.extension, size: 20),
                        ),
                        title: Text(
                          '${item.part.partNumber} - ${item.part.description}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        subtitle: Text(
                          'Modelos: ${item.part.compatibleModels.join(", ")}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Text(
                            '${item.quantity} ud.',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final newStockItems = widget.stockService.newStockItems.where((item) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return item.partNumber.toLowerCase().contains(q) ||
          item.description.toLowerCase().contains(q) ||
          item.brand.toLowerCase().contains(q);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // PESTAÑA PRINCIPAL: Stock Físico (Cajones) vs Stock Nuevos (Excel)
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Stock Físico (Cajones)'), icon: Icon(Icons.grid_view)),
              ButtonSegment(value: 1, label: Text('Stock Nuevos (Excel)'), icon: Icon(Icons.shopping_bag)),
            ],
            selected: {_selectedMainTab},
            onSelectionChanged: (set) => setState(() => _selectedMainTab = set.first),
          ),
          const SizedBox(height: 12),

          // SI ESTAMOS EN STOCK FÍSICO
          if (_selectedMainTab == 0) ...[
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Mapa de Cajones'), icon: Icon(Icons.apps)),
                      ButtonSegment(value: 1, label: Text('Lista por Repuesto'), icon: Icon(Icons.format_list_bulleted)),
                    ],
                    selected: {_physicalSubView},
                    onSelectionChanged: (set) => setState(() => _physicalSubView = set.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            TextField(
              decoration: InputDecoration(
                labelText: 'Buscar por Part Number, Descripción o Modelo',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
            ),
            const SizedBox(height: 12),

            // SUB-VISTA 1: MUEBLE VIRTUAL (GRILLA DE 20 CAJONES)
            if (_physicalSubView == 0)
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: 1.1,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: 20,
                  itemBuilder: (context, index) {
                    final drawerNumber = index + 1;
                    final itemsInDrawer = _getPartsInDrawer(drawerNumber);
                    final totalQty = itemsInDrawer.fold<int>(0, (sum, item) => sum + item.quantity);
                    final hasStock = itemsInDrawer.isNotEmpty;

                    bool isMatch = false;
                    if (_searchQuery.isNotEmpty) {
                      final q = _searchQuery.toLowerCase();
                      isMatch = itemsInDrawer.any((item) {
                        return item.part.partNumber.toLowerCase().contains(q) ||
                            item.part.description.toLowerCase().contains(q) ||
                            item.part.compatibleModels.any((m) => m.toLowerCase().contains(q));
                      });
                    }

                    return InkWell(
                      onTap: () => _showDrawerDetailsDialog(drawerNumber),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isMatch
                              ? Colors.amber.shade100
                              : (hasStock ? Colors.blue.shade50 : Colors.grey.shade100),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isMatch
                                ? Colors.amber.shade800
                                : (hasStock ? Colors.blue.shade400 : Colors.grey.shade300),
                            width: isMatch ? 2.5 : (hasStock ? 1.5 : 1),
                          ),
                          boxShadow: hasStock
                              ? [
                                  BoxShadow(
                                    color: Colors.blue.shade100.withOpacity(0.5),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  )
                                ]
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'CAJÓN',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: hasStock ? Colors.blue.shade900 : Colors.grey.shade600,
                              ),
                            ),
                            Text(
                              '$drawerNumber',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: hasStock ? Colors.blueAccent : Colors.grey.shade500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: hasStock ? Colors.blueAccent : Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                hasStock ? '$totalQty ud.' : 'Vacío',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: hasStock ? Colors.white : Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

            // SUB-VISTA 2: LISTA EXPANDIBLE
            if (_physicalSubView == 1)
              Expanded(
                child: ListView.builder(
                  itemCount: widget.stockService.parts.length,
                  itemBuilder: (context, index) {
                    final part = widget.stockService.parts[index];
                    final totalStock = widget.stockService.getTotalStockForPart(part.id);
                    final drawerMap = widget.stockService.getDrawerBreakdownForPart(part.id);

                    if (_searchQuery.isNotEmpty) {
                      final q = _searchQuery.toLowerCase();
                      final match = part.partNumber.toLowerCase().contains(q) ||
                          part.description.toLowerCase().contains(q) ||
                          part.compatibleModels.any((m) => m.toLowerCase().contains(q));
                      if (!match) return const SizedBox.shrink();
                    }

                    return Card(
                      child: ExpansionTile(
                        leading: const Icon(Icons.extension, color: Colors.blue),
                        title: Text('${part.partNumber} - ${part.description}'),
                        subtitle: Text('Stock Total: $totalStock ud. | Modelos: ${part.compatibleModels.join(", ")}'),
                        children: drawerMap.entries.map((e) {
                          return ListTile(
                            dense: true,
                            title: Text('Cajón ${e.key}'),
                            trailing: Text('${e.value} ud.', style: const TextStyle(fontWeight: FontWeight.bold)),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
              ),
          ],

          // SI ESTAMOS EN STOCK NUEVOS (COMPRAS)
          if (_selectedMainTab == 1) ...[
            TextField(
              decoration: InputDecoration(
                labelText: 'Buscar en Stock Nuevos (PN, Descripción o Marca)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: newStockItems.isEmpty
                  ? const Center(child: Text('No hay artículos nuevos para el filtro aplicado.'))
                  : ListView.builder(
                      itemCount: newStockItems.length,
                      itemBuilder: (context, index) {
                        final item = newStockItems[index];
                        return Card(
                          color: Colors.green.shade50,
                          child: ListTile(
                            leading: const Icon(Icons.new_releases, color: Colors.green),
                            title: Text('${item.partNumber} - ${item.description}'),
                            subtitle: Text('Marca: ${item.brand} | Familia: ${item.family}'),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(12)),
                              child: Text(
                                '${item.currentStock} ${item.unit}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }
}