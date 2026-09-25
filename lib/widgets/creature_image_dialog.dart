import 'dart:io';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/art/art_cache_service.dart';
import '../models/creature.dart';

Future<void> showCreatureImage(
  BuildContext context, {
  required Creature creature,
  required ArtCacheService art,
}) async {
  final file = await art.displayFileFor(creature.id);
  final exists = await file.exists();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) {
      return Dialog(
        backgroundColor: momirField,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                creature.name,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: exists
                    ? Image.file(File(file.path), fit: BoxFit.contain)
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Изображение ещё не скачано. Откройте базу и нажмите «Докачать изображения».',
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
    },
  );
}
