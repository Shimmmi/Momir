import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/art/art_cache_service.dart';
import '../../core/constants.dart';
import '../../core/db/creature_repository.dart';
import '../../models/creature.dart';
import '../../widgets/creature_image_dialog.dart';
import '../../widgets/mana_symbol.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _query = TextEditingController();
  final _colors = <String>{};
  int? _cmc;
  String? _setCode;
  var _sortByCmc = false;
  var _loading = false;
  var _offset = 0;
  var _hasMore = true;
  List<({String code, String name})> _sets = const [];
  final _cards = <Creature>[];

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final sets = await context.read<CreatureRepository>().sets();
    if (!mounted) return;
    setState(() => _sets = sets);
    await _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = false;
      _offset = 0;
      _hasMore = true;
      _cards.clear();
    });
    await _more();
  }

  Future<void> _more() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    final repo = context.read<CreatureRepository>();
    final page = await repo.search(
      query: _query.text,
      cmc: _cmc,
      colors: _colors,
      setCode: _setCode,
      sortByCmc: _sortByCmc,
      offset: _offset,
    );
    if (!mounted) return;
    setState(() {
      _cards.addAll(page);
      _offset += page.length;
      _hasMore = page.length == 60;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('База карт'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/menu'),
        ),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: () => context.push('/sync'),
            icon: const Icon(Icons.cloud_sync_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _query,
              decoration: const InputDecoration(
                hintText: 'Имя существа',
                isDense: true,
              ),
              onSubmitted: (_) => _reload(),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('Любая мана'),
                    selected: _cmc == null,
                    onSelected: (_) {
                      setState(() => _cmc = null);
                      _reload();
                    },
                  ),
                ),
                for (var i = 0; i <= kMaxExactCmc; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text('$i'),
                      selected: _cmc == i,
                      onSelected: (_) {
                        setState(() => _cmc = _cmc == i ? null : i);
                        _reload();
                      },
                    ),
                  ),
                FilterChip(
                  label: Text('${kMaxExactCmc + 1}+'),
                  selected: _cmc == kMaxExactCmc + 1,
                  onSelected: (_) {
                    setState(() {
                      _cmc = _cmc == kMaxExactCmc + 1 ? null : kMaxExactCmc + 1;
                    });
                    _reload();
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final c in const ['W', 'U', 'B', 'R', 'G'])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      avatar: ManaSymbol(code: c, size: 16),
                      label: Text(c),
                      selected: _colors.contains(c),
                      onSelected: (_) {
                        setState(() {
                          if (!_colors.add(c)) _colors.remove(c);
                        });
                        _reload();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<String?>(
                    isExpanded: true,
                    value: _setCode,
                    hint: const Text('Все сеты'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Все сеты'),
                      ),
                      for (final set in _sets)
                        DropdownMenuItem<String?>(
                          value: set.code,
                          child: Text(
                            set.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() => _setCode = value);
                      _reload();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    setState(() => _sortByCmc = !_sortByCmc);
                    _reload();
                  },
                  child: Text(_sortByCmc ? 'По мане' : 'По имени'),
                ),
              ],
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (note) {
                if (note.metrics.pixels > note.metrics.maxScrollExtent - 240) {
                  _more();
                }
                return false;
              },
              child: ListView.builder(
                itemCount: _cards.length + (_loading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= _cards.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final card = _cards[index];
                  final art = context.read<ArtCacheService>();
                  return ListTile(
                    leading: _LibraryThumb(id: card.id, art: art),
                    title: Text(card.name),
                    subtitle: Text(
                      '${card.cmc} · ${card.setName ?? card.setCode ?? ''}',
                    ),
                    onTap: () => showCreatureImage(
                      context,
                      creature: card,
                      art: art,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryThumb extends StatelessWidget {
  const _LibraryThumb({required this.id, required this.art});

  final String id;
  final ArtCacheService art;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File>(
      future: art.displayFileFor(id),
      builder: (context, snap) {
        final file = snap.data;
        if (file == null || !file.existsSync()) {
          return const SizedBox(
            width: 36,
            height: 50,
            child: ColoredBox(color: momirLine),
          );
        }
        return Image.file(file, width: 36, height: 50, fit: BoxFit.cover);
      },
    );
  }
}
