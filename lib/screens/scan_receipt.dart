import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/receipt_scan_result.dart';
import '../services/ocr_service.dart';
import '../services/receipt_parser.dart';
import '../utils/formatters.dart';

class ScanReceiptScreen extends StatefulWidget {
  final String preferredCurrencyCode;

  const ScanReceiptScreen({
    super.key,
    this.preferredCurrencyCode = 'EGP',
  });

  @override
  State<ScanReceiptScreen> createState() => _ScanReceiptScreenState();
}

class _ScanReceiptScreenState extends State<ScanReceiptScreen> {
  final _picker = ImagePicker();
  final _ocr = OcrService();
  final _parser = ReceiptParser();

  XFile? _image;
  ReceiptScanResult? _result;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _recoverLostImage();
  }

  Future<void> _recoverLostImage() async {
    try {
      final response = await _picker.retrieveLostData();
      if (response.isEmpty || response.files == null || response.files!.isEmpty) return;
      await _process(response.files!.first);
    } catch (_) {
      // Recovery is best-effort and only relevant on Android process restarts.
    }
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final image = await _picker.pickImage(
        source: source,
        imageQuality: 95,
        maxWidth: 2800,
      );
      if (image != null) await _process(image);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'Could not open the ${source == ImageSource.camera ? 'camera' : 'gallery'}.');
    }
  }

  Future<void> _process(XFile image) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _image = image;
    });

    try {
      final text = await _ocr.recognize(image.path);
      if (text.trim().isEmpty) throw const FormatException('No readable text found');
      final parsed = _parser.parse(text);
      if (!mounted) return;
      setState(() => _result = parsed);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'I could not read this receipt clearly. Try a brighter, flatter photo with the full receipt visible.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final result = _result;
    final detectedCurrency = result?.currencyCode ?? widget.preferredCurrencyCode;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan receipt')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Container(
              height: 270,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(28),
              ),
              child: _image == null
                  ? _ScannerPlaceholder(color: scheme.primary)
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(_image!.path), fit: BoxFit.cover),
                        if (_loading)
                          Container(
                            color: Colors.black45,
                            alignment: Alignment.center,
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: Colors.white),
                                SizedBox(height: 12),
                                Text(
                                  'Reading merchant, total, date & tax…',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(Icons.tips_and_updates_outlined, size: 20),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Best results: fill the frame, avoid shadows, keep the receipt flat, and include the total line.',
                      style: TextStyle(fontSize: 12, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _loading ? null : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: Text(_image == null ? 'Camera' : 'Retake'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_rounded),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, color: scheme.onErrorContainer),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer))),
                  ],
                ),
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Detected details',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  _ConfidenceChip(value: result.confidence),
                ],
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      _ResultRow(label: 'Merchant', value: result.store),
                      const Divider(height: 24),
                      _ResultRow(
                        label: 'Total',
                        value: result.amount == null
                            ? 'Review manually'
                            : AppFormatters.money(result.amount!, currencyCode: detectedCurrency),
                      ),
                      const Divider(height: 24),
                      _ResultRow(label: 'Currency', value: result.currencyCode ?? 'Not detected'),
                      if (result.taxAmount != null) ...[
                        const Divider(height: 24),
                        _ResultRow(
                          label: 'VAT / tax',
                          value: AppFormatters.money(result.taxAmount!, currencyCode: detectedCurrency),
                        ),
                      ],
                      const Divider(height: 24),
                      _ResultRow(label: 'Category', value: result.category),
                      const Divider(height: 24),
                      _ResultRow(
                        label: 'Date',
                        value: result.date == null ? 'Today' : AppFormatters.date(result.date!),
                      ),
                      if (result.receiptNumber != null) ...[
                        const Divider(height: 24),
                        _ResultRow(label: 'Receipt #', value: result.receiptNumber!),
                      ],
                    ],
                  ),
                ),
              ),
              if (result.currencyCode != null && result.currencyCode != widget.preferredCurrencyCode) ...[
                const SizedBox(height: 10),
                Text(
                  'This receipt looks like ${result.currencyCode}, while your app currency is ${widget.preferredCurrencyCode}. The amount is not converted automatically.',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, result),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Use these details'),
              ),
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                title: const Text('OCR text'),
                subtitle: const Text('Verify anything the scanner may have misread'),
                children: [
                  SelectableText(
                    result.rawText,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.45),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'Receipt text is processed on this device. Your image and spending data are not uploaded by this app.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  final double value;

  const _ConfidenceChip({required this.value});

  @override
  Widget build(BuildContext context) {
    final percent = (value * 100).round();
    return Chip(
      avatar: Icon(
        value >= 0.7 ? Icons.verified_rounded : Icons.fact_check_outlined,
        size: 18,
      ),
      label: Text('$percent% match'),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ScannerPlaceholder extends StatelessWidget {
  final Color color;

  const _ScannerPlaceholder({required this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_rounded, size: 64, color: color),
          const SizedBox(height: 14),
          const Text('Capture a clear receipt', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 6),
          Text(
            'Merchant, total, currency, date and tax can be detected.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;

  const _ResultRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}
