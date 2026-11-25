import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:stock_tracker/services/firestore_stock_service.dart';
import '../models/user_role.dart';
import '../models/new_stock_item.dart';

class AdminPanelScreen extends StatefulWidget {
  final FirestoreStockService stockService;

  const AdminPanelScreen({super.key, required this.stockService});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final _pnCatalogController = TextEditingController();
  final _descCatalogController = TextEditingController();
  final _modelCatalogController = TextEditingController();

  bool _isUploading = false;
  bool _isExporting = false;

  @override
  void dispose() {
    _pnCatalogController.dispose();
    _descCatalogController.dispose();
    _modelCatalogController.dispose();
    super.dispose();
  }

  /// Carga de Excel "Stock Nuevos" (Tango ERP)
  Future<void> _pickAndParseExcel() async {
    setState(() => _isUploading = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _isUploading = false);
        return;
      }

      final fileBytes = result.files.first.bytes;
      if (fileBytes == null) {
        throw Exception('No se pudieron leer los datos del archivo.');
      }

      final excel = Excel.decodeBytes(fileBytes);
      final List<NewStockItem> parsedItems = [];

      for (var table in excel.tables.keys) {
        final sheet = excel.tables[table];
        if (sheet == null) continue;

        int headerRowIndex = -1;
        int colArticulo = -1;
        int colNombre1 = -1;
        int colUM = -1;
        int colStockActual = -1;
        int colFamilia = -1;
        int colMarca = -1;

        for (int i = 0; i < sheet.maxRows; i++) {
          final row = sheet.rows[i];
          for (int j = 0; j < row.length; j++) {
            final val = row[j]?.value?.toString().trim() ?? '';
            if (val == 'Artículo') {
              headerRowIndex = i;
              colArticulo = j;
            } else if (val == 'Nombre_1') {
              colNombre1 = j;
            } else if (val == 'U.M.') {
              colUM = j;
            } else if (val == 'Stock actual') {
              colStockActual = j;
            } else if (val == 'Nombre_2' || val == 'FAMILIA') {
              if (colFamilia == -1) colFamilia = j;
            } else if (val == 'Nombre_3' || val == 'MARCA') {
              if (colMarca == -1) colMarca = j;
            }
          }
          if (headerRowIndex != -1) break;
        }

        if (headerRowIndex == -1) continue;

        for (int i = headerRowIndex + 1; i < sheet.maxRows; i++) {
          final row = sheet.rows[i];
          if (row.isEmpty) continue;

          final partNumber = (colArticulo != -1 && colArticulo < row.length)
              ? row[colArticulo]?.value?.toString().trim() ?? ''
              : '';

          if (partNumber.isEmpty) continue;

          final description = (colNombre1 != -1 && colNombre1 < row.length)
              ? row[colNombre1]?.value?.toString().trim() ?? ''
              : '';
          final unit = (colUM != -1 && colUM < row.length)
              ? row[colUM]?.value?.toString().trim() ?? 'UN'
              : 'UN';
          final stockStr = (colStockActual != -1 && colStockActual < row.length)
              ? row[colStockActual]?.value?.toString().trim() ?? '0'
              : '0';

          final currentStock = int.tryParse(stockStr) ??
              (double.tryParse(stockStr)?.toInt() ?? 0);

          final family = (colFamilia != -1 && colFamilia < row.length)
              ? row[colFamilia]?.value?.toString().trim() ?? ''
              : '';
          final brand = (colMarca != -1 && colMarca < row.length)
              ? row[colMarca]?.value?.toString().trim() ?? ''
              : '';

          parsedItems.add(NewStockItem(
            partNumber: partNumber,
            description: description,
            unit: unit,
            currentStock: currentStock,
            family: family,
            brand: brand,
          ));
        }
      }

      if (parsedItems.isNotEmpty) {
        widget.stockService.loadNewStockItems(parsedItems);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Se cargaron ${parsedItems.length} artículos de Stock Nuevos correctamente.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se encontraron registros válidos en el archivo Excel.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al procesar el Excel: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isUploading = false);
    }
  }

  /// Generación y Exportación Completa de Toda la Data a un Archivo Excel (.xlsx)
  Future<void> _exportFullReportToExcel() async {
    setState(() => _isExporting = true);

    try {
      final excel = Excel.createExcel();

      // Pestaña 1: Catálogo General
      final Sheet sheetCatalog = excel['Catálogo de Repuestos'];
      sheetCatalog.appendRow([
        TextCellValue('Part Number'),
        TextCellValue('Descripción'),
        TextCellValue('Modelos Compatibles'),
        TextCellValue('Stock Mínimo'),
        TextCellValue('Stock Máximo'),
        TextCellValue('Safe Time (Días)'),
        TextCellValue('Stock Físico Total')
      ]);

      for (var part in widget.stockService.parts) {
        final totalStock = widget.stockService.getTotalStockForPart(part.id);
        sheetCatalog.appendRow([
          TextCellValue(part.partNumber),
          TextCellValue(part.description),
          TextCellValue(part.compatibleModels.join(', ')),
          IntCellValue(part.minStock),
          IntCellValue(part.maxStock),
          IntCellValue(part.safeTimeDays),
          IntCellValue(totalStock),
        ]);
      }

      // Pestaña 2: Stock Físico en Cajones
      final Sheet sheetDrawers = excel['Stock en Cajones'];
      sheetDrawers.appendRow([
        TextCellValue('Cajón N°'),
        TextCellValue('Part Number'),
        TextCellValue('Descripción'),
        TextCellValue('Cantidad')
      ]);

      for (var stock in widget.stockService.stocks) {
        final partList = widget.stockService.parts.where((p) => p.id == stock.partId);
        if (partList.isNotEmpty) {
          final part = partList.first;
          sheetDrawers.appendRow([
            IntCellValue(stock.drawerNumber),
            TextCellValue(part.partNumber),
            TextCellValue(part.description),
            IntCellValue(stock.quantity),
          ]);
        }
      }

      // Pestaña 3: Stock Nuevos (Compras)
      final Sheet sheetNewStock = excel['Stock Nuevos (Excel)'];
      sheetNewStock.appendRow([
        TextCellValue('Part Number'),
        TextCellValue('Descripción'),
        TextCellValue('Unidad'),
        TextCellValue('Stock Actual'),
        TextCellValue('Familia'),
        TextCellValue('Marca')
      ]);

      for (var item in widget.stockService.newStockItems) {
        sheetNewStock.appendRow([
          TextCellValue(item.partNumber),
          TextCellValue(item.description),
          TextCellValue(item.unit),
          IntCellValue(item.currentStock),
          TextCellValue(item.family),
          TextCellValue(item.brand),
        ]);
      }

      // Pestaña 4: Historial Completo de Movimientos y Transferencias
      final Sheet sheetMovements = excel['Historial Movimientos'];
      sheetMovements.appendRow([
        TextCellValue('Fecha y Hora'),
        TextCellValue('Tipo Operación'),
        TextCellValue('Part Number'),
        TextCellValue('Cantidad'),
        TextCellValue('Cajón'),
        TextCellValue('Serial Origen'),
        TextCellValue('Serial Destino'),
        TextCellValue('Operador')
      ]);

      for (var m in widget.stockService.movements) {
        sheetMovements.appendRow([
          TextCellValue(m.timestamp.toString().substring(0, 19)),
          TextCellValue(m.type.name.toUpperCase()),
          TextCellValue(m.partNumber),
          IntCellValue(m.quantity),
          IntCellValue(m.drawerNumber),
          TextCellValue(m.sourceMachine ?? '-'),
          TextCellValue(m.targetMachine ?? '-'),
          TextCellValue(m.userName),
        ]);
      }

      // Eliminar hoja por defecto si se creó una adicional
      if (excel.tables.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      final fileBytes = excel.save();
      if (fileBytes != null) {
        final String? outputPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar Reporte General de Stock',
          fileName: 'Reporte_Stock_Control_${DateTime.now().millisecondsSinceEpoch}.xlsx',
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
          bytes: Uint8List.fromList(fileBytes),
        );

        if (outputPath != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ Reporte Excel exportado con éxito en: $outputPath'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al exportar reporte Excel: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isExporting = false);
    }
  }

  void _addCatalogPart() {
    final pn = _pnCatalogController.text.trim();
    final desc = _descCatalogController.text.trim();
    final model = _modelCatalogController.text.trim();

    if (pn.isEmpty || desc.isEmpty || model.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor completa todos los campos obligatorios.')),
      );
      return;
    }

    try {
      widget.stockService.addPartToCatalog(
        partNumber: pn,
        description: desc,
        compatibleModels: [model],
      );
      _pnCatalogController.clear();
      _descCatalogController.clear();
      _modelCatalogController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✓ "$pn" registrado en la Base de Datos'), backgroundColor: Colors.green),
      );
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.stockService.currentUser;
    final isAdvanced = user.role == UserRole.advancedAdmin;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isAdvanced ? Colors.purple.shade50 : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isAdvanced ? Colors.purple : Colors.blue),
            ),
            child: Row(
              children: [
                Icon(isAdvanced ? Icons.admin_panel_settings : Icons.security,
                    color: isAdvanced ? Colors.purple : Colors.blue, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Usuario Activo: ${user.name}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('Rol: ${user.roleDisplayName}',
                          style: TextStyle(color: isAdvanced ? Colors.purple.shade900 : Colors.blue.shade900)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // SECCIÓN 1: Reportes y Exportación Completa
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('1. Reporte General de Auditoría',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  const Text('Descarga toda la base de datos, cajones, compras e historial de movimientos en un archivo Excel.',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _isExporting ? null : _exportFullReportToExcel,
                      icon: _isExporting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.file_download),
                      label: Text(_isExporting ? 'GENERANDO REPORTE...' : 'DESCARGAR REPORTE COMPLETO (.XLSX)'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // SECCIÓN 2: Importación Tango ERP
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('2. Cargar Excel "Stock Nuevos" (Tango STO2040)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  const Text('Sube la planilla de compras para actualizar el catálogo de Stock Nuevos.',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _isUploading ? null : _pickAndParseExcel,
                      icon: _isUploading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.upload_file),
                      label: Text(_isUploading ? 'PROCESANDO EXCEL...' : 'SUBIR EXCEL DE COMPRAS (.XLSX)'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // SECCIÓN 3: Alta Manual en Catálogo
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('3. Alta Individual en Catálogo (DB)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pnCatalogController,
                    decoration: const InputDecoration(labelText: 'Part Number *', border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _descCatalogController,
                    decoration: const InputDecoration(labelText: 'Descripción *', border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _modelCatalogController,
                    decoration: const InputDecoration(labelText: 'Modelo Compatible *', border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                      onPressed: _addCatalogPart,
                      icon: const Icon(Icons.save),
                      label: const Text('AGREGAR A LA BASE DE DATOS'),
                    ),
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // SECCIÓN 4: Gestión de Usuarios (Facu)
          if (isAdvanced)
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('4. Gestión de Jerarquía de Usuarios (Facu)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const Divider(),
                    ...widget.stockService.users.map((u) {
                      return ListTile(
                        title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(u.roleDisplayName),
                        trailing: DropdownButton<UserRole>(
                          value: u.role,
                          items: UserRole.values.map((role) {
                            return DropdownMenuItem(
                              value: role,
                              child: Text(AppUser(id: '', name: '', role: role).roleDisplayName),
                            );
                          }).toList(),
                          onChanged: (newRole) {
                            if (newRole != null) {
                              widget.stockService.updateUserRole(u.id, newRole);
                              setState(() {});
                            }
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}