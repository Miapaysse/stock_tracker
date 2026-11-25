import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerDialog extends StatefulWidget {
  final String title;

  const BarcodeScannerDialog({super.key, this.title = 'Escanear Código'});

  @override
  State<BarcodeScannerDialog> createState() => _BarcodeScannerDialogState();
}

class _BarcodeScannerDialogState extends State<BarcodeScannerDialog> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
    formats: const [BarcodeFormat.all], // Habilita la lectura de todos los formatos de código
  );

  bool _isScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: ValueListenableBuilder(
                valueListenable: _controller,
                builder: (context, state, child) {
                  return Icon(
                    state.torchState == TorchState.on ? Icons.flash_on : Icons.flash_off,
                    color: state.torchState == TorchState.on ? Colors.amber : Colors.white,
                  );
                },
              ),
              onPressed: () => _controller.toggleTorch(),
            ),
            IconButton(
              icon: const Icon(Icons.cameraswitch),
              onPressed: () => _controller.switchCamera(),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context, null),
            ),
          ],
        ),
        body: Stack(
          children: [
            MobileScanner(
              controller: _controller,
              onDetect: (capture) {
                if (_isScanned) return;
                final List<Barcode> barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  if (barcode.rawValue != null && barcode.rawValue!.trim().isNotEmpty) {
                    _isScanned = true;
                    Navigator.pop(context, barcode.rawValue!.trim());
                    break;
                  }
                }
              },
            ),
            Center(
              child: Container(
                width: 290,
                height: 190,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.greenAccent, width: 3),
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.black.withOpacity(0.15),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.qr_code_scanner, color: Colors.greenAccent, size: 44),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        widget.title,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}