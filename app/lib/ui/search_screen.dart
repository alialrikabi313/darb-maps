// البحث عن وجهة.
//
// محلي بالكامل — يشتغل بلا شبكة. البحث يبدأ بعد حرفين وبتأخير قصير:
// استعلام FTS على كل حرف يُحسّ تأخّراً في الكتابة على جهاز متوسط.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../core/search.dart';
import '../nav/phrases.dart';
import '../state/app_state.dart';

/// تصنيفات الوصول السريع قبل ما يكتب المستخدم شيئاً.
const _quickCategories = <String, (String, IconData)>{
  'fuel': ('وقود', Icons.local_gas_station),
  'hospital': ('مستشفى', Icons.local_hospital),
  'pharmacy': ('صيدلية', Icons.medical_services),
  'restaurant': ('مطعم', Icons.restaurant),
  'market': ('سوق', Icons.shopping_cart),
  'mosque': ('جامع', Icons.mosque),
};

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  List<Place> _results = const [];
  bool _searching = false;
  String? _activeCategory;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _activeCategory = null;

    if (value.trim().length < Cfg.searchMinChars) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }

    setState(() => _searching = true);
    _debounce = Timer(Cfg.searchDebounce, () => _run(value));
  }

  Future<void> _run(String query) async {
    final app = context.read<AppState>();
    final hits = await app.search.search(query, near: app.fix?.pos);
    if (!mounted) return;
    setState(() {
      _results = hits;
      _searching = false;
    });
  }

  Future<void> _runCategory(String category) async {
    final app = context.read<AppState>();
    setState(() {
      _searching = true;
      _activeCategory = category;
      _controller.clear();
    });

    final hits = await app.search.nearby(app.center,
        categories: [category], radiusM: 8000, limit: 30);
    if (!mounted) return;
    setState(() {
      _results = hits;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          decoration: const InputDecoration(
            hintText: 'ابحث عن مكان أو شارع',
            border: InputBorder.none,
          ),
          style: const TextStyle(fontSize: 17),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 54,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              children: [
                for (final e in _quickCategories.entries)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: FilterChip(
                      avatar: Icon(e.value.$2, size: 17),
                      label: Text(e.value.$1),
                      selected: _activeCategory == e.key,
                      onSelected: (_) => _runCategory(e.key),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_results.isEmpty) {
      final typed = _controller.text.trim().length >= Cfg.searchMinChars;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            typed
                // نقول السبب المحتمل لا «لا نتائج» وبس: 8% فقط من طرق
                // العراق مسمّاة في OSM، وهذا أرجح سبب الفشل
                ? 'ما لقينا شي بهذا الاسم.\n\nجرّب اسم المنطقة أو معلماً '
                    'قريباً — أسماء الشوارع ناقصة في خريطة العراق المفتوحة.'
                : 'اكتب اسم مكان، أو اختر تصنيفاً من الأعلى',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF6B7280), height: 1.5),
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 64),
      itemBuilder: (_, i) {
        final p = _results[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFE8EEF6),
            child: Icon(_iconFor(p.category),
                color: const Color(0xFF2D7FF9), size: 20),
          ),
          title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              categoryLabels[p.category] ?? p.category,
              if (p.distanceM != null) distanceLabel(p.distanceM!),
              if (p.tags['addr:street'] != null) '${p.tags['addr:street']}',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () =>
              Navigator.of(context).pop(Destination(p.title, p.pos)),
        );
      },
    );
  }

  static IconData _iconFor(String category) =>
      _quickCategories[category]?.$2 ??
      switch (category) {
        'place' => Icons.location_city,
        'street' => Icons.add_road,
        'school' || 'university' => Icons.school,
        'bank' => Icons.account_balance,
        'government' => Icons.account_balance_outlined,
        'transport' => Icons.directions_bus,
        'hotel' => Icons.hotel,
        'park' => Icons.park,
        _ => Icons.place,
      };
}
