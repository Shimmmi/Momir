import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../core/art/art_cache_service.dart';
import '../core/ble/printer_connection_service.dart';
import '../features/printer_setup/printer_picker.dart';
import '../models/creature.dart';
import '../services/print_service.dart';
import 'card_renderer.dart';

Future<void> showCreatureImage(
  BuildContext context, {
  required Creature creature,
  required ArtCacheService art,
}) async {
  final file = await art.displayFileFor(creature.id);
  final hasColor = await file.exists();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) {
      return _CreatureImageDialog(
        creature: creature,
        art: art,
        colorFile: hasColor ? file : null,
      );
    },
  );
}

class _CreatureImageDialog extends StatefulWidget {
  const _CreatureImageDialog({
    required this.creature,
    required this.art,
    required this.colorFile,
  });

  final Creature creature;
  final ArtCacheService art;
  final File? colorFile;

  @override
  State<_CreatureImageDialog> createState() => _CreatureImageDialogState();
}

class _CreatureImageDialogState extends State<_CreatureImageDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flip;
  PrintableCard? _printable;
  var _printing = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _flip = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _loadMomir();
  }

  Future<void> _loadMomir() async {
    final renderer = context.read<CardRenderService>();
    final printFile = await widget.art.fileFor(widget.creature.id);
    final bytes = await printFile.exists() ? await printFile.readAsBytes() : null;
    final card = await renderer.renderCreature(
      widget.creature,
      artJpeg: bytes,
    );
    if (mounted) setState(() => _printable = card);
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  void _toggleSide() {
    if (_flip.isAnimating) return;
    if (_flip.value == 0) {
      _flip.forward();
    } else {
      _flip.reverse();
    }
  }

  Future<void> _print() async {
    final card = _printable;
    if (card == null || _printing) return;
    final printer = context.read<PrinterConnectionService>();
    final prints = context.read<PrintService>();
    if (!printer.isConnected) {
      await showPrinterPicker(context);
      if (!mounted || !printer.isConnected) return;
    }
    setState(() {
      _printing = true;
      _status = 'Идёт печать…';
    });
    try {
      await prints.printCard(card);
      if (mounted) setState(() => _status = 'Готово. Оторвите чек.');
    } catch (_) {
      if (mounted) setState(() => _status = 'Печать не прошла.');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: momirField,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              widget.creature.name,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),
          Flexible(
            child: GestureDetector(
              onTap: _toggleSide,
              child: AnimatedBuilder(
                animation: _flip,
                builder: (context, _) {
                  final angle = _flip.value * math.pi;
                  final showMomir = angle > math.pi / 2;
                  final rotation = showMomir ? angle - math.pi : angle;
                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateY(rotation),
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: showMomir ? _momirSide() : _colorSide(),
                    ),
                  );
                },
              ),
            ),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                _status!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: FilledButton(
              onPressed: _printable == null || _printing ? null : _print,
              child: const Text('Печать'),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Widget _colorSide() {
    final file = widget.colorFile;
    if (file == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Изображение ещё не скачано. Откройте базу и нажмите «Докачать изображения».',
          textAlign: TextAlign.center,
        ),
      );
    }
    return Image.file(File(file.path), fit: BoxFit.contain);
  }

  Widget _momirSide() {
    final card = _printable;
    if (card == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return ColoredBox(
      color: momirPaper,
      child: Image.memory(card.pngBytes, fit: BoxFit.contain),
    );
  }
}
