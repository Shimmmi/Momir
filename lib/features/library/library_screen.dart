import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/art/art_cache_service.dart';
import '../../core/constants.dart';
import '../../core/db/creature_repository.dart';
import '../../core/game_mode.dart';
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
  final _setQuery = TextEditingController();
  final _colors = <String>{};
  int? _cmc;
  GameMode? _type;
  String? _setCode;
  var _sortByCmc = false;
  var _loading = false;
  var _offset = 0;
  var _hasMore = true;
  List<({String code, String name})> _sets = const [];
  List<({String code, String name})> _setHits = const [];
  final _cards = <Creature>[];

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _query.dispose();
    _setQuery.dispose();
    super.dispose();
  }

  Future<void> _confirmDeleteImages(BuildContext context) async {
    final art = context.read<ArtCacheService>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить все изображения?'),
        content: const Text(
          'Картинки на телефоне будут стёрты. База карт и партии останутся. Потом их можно скачать снова.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await art.deleteAllImages();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Изображения удалены')));
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
      mode: _type,
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

  void _onSetQuery(String raw) {
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() {
        _setHits = const [];
        _setCode = null;
      });
      _reload();
      return;
    }
    final hits = _sets.where((set) => _matchesSet(set, q)).toList()
      ..sort((a, b) => _setRank(a, q).compareTo(_setRank(b, q)));
    setState(() {
      _setHits = hits.take(6).toList();
      _setCode = hits.isEmpty ? null : hits.first.code;
    });
    _reload();
  }

  void _pickSet(({String code, String name}) set) {
    _setQuery.value = TextEditingValue(
      text: set.name,
      selection: TextSelection.collapsed(offset: set.name.length),
    );
    setState(() {
      _setCode = set.code;
      _setHits = const [];
    });
    _reload();
  }

  bool _matchesSet(({String code, String name}) set, String q) {
    return set.name.toLowerCase().contains(q) ||
        set.code.toLowerCase().contains(q);
  }

  int _setRank(({String code, String name}) set, String q) {
    final code = set.code.toLowerCase();
    final name = set.name.toLowerCase();
    if (code == q) return 0;
    if (code.startsWith(q)) return 1;
    if (code.contains(q)) return 2;
    if (name.startsWith(q)) return 3;
    return 4;
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
            tooltip: 'Удалить изображения',
            onPressed: () => _confirmDeleteImages(context),
            icon: const Icon(Icons.delete_outline),
          ),
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
                hintText: 'Имя карты',
                isDense: true,
              ),
              onSubmitted: (_) => _reload(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _CmcGrid(
              selected: _cmc,
              onPick: (value) {
                setState(() => _cmc = value);
                _reload();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                FilterChip(
                  label: const Text('Все'),
                  selected: _type == null,
                  onSelected: (_) {
                    setState(() => _type = null);
                    _reload();
                  },
                ),
                for (final mode in GameMode.values)
                  FilterChip(
                    label: Text(mode.typeLabel),
                    selected: _type == mode,
                    onSelected: (_) {
                      setState(() => _type = _type == mode ? null : mode);
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
                  child: TextField(
                    controller: _setQuery,
                    decoration: const InputDecoration(
                      hintText: 'Сет',
                      isDense: true,
                    ),
                    onChanged: _onSetQuery,
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
          if (_setHits.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Column(
                children: [
                  for (final set in _setHits)
                    _SetHit(
                      name: set.name,
                      highlighted: set.code == _setCode,
                      onTap: () => _pickSet(set),
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
                    onTap: () =>
                        showCreatureImage(context, creature: card, art: art),
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

class _CmcGrid extends StatelessWidget {
  const _CmcGrid({required this.selected, required this.onPick});

  final int? selected;
  final ValueChanged<int?> onPick;

  @override
  Widget build(BuildContext context) {
    final labels = <int?, String>{
      null: 'Все',
      for (var i = 0; i <= kMaxExactCmc; i++) i: '$i',
      kMaxExactCmc + 1: '${kMaxExactCmc + 1}+',
    };
    return GridView.count(
      crossAxisCount: 9,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      childAspectRatio: 1.15,
      children: [
        for (final entry in labels.entries)
          _CmcCell(
            label: entry.value,
            selected: selected == entry.key,
            onTap: () => onPick(selected == entry.key ? null : entry.key),
          ),
      ],
    );
  }
}

class _CmcCell extends StatelessWidget {
  const _CmcCell({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? momirPaper : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: selected ? momirPaper : momirLine),
      ),
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? momirInk : momirPaper,
            ),
          ),
        ),
      ),
    );
  }
}

class _SetHit extends StatelessWidget {
  const _SetHit({
    required this.name,
    required this.highlighted,
    required this.onTap,
  });

  final String name;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlighted ? const Color(0x33E4C56A) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: highlighted ? momirGold : momirPaper,
                fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
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
