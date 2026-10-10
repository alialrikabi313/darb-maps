// تخطيط الرحلة: عدة محطات بمسار واحد.
//
// لماذا شاشة لا ورقة سفلية: إعادة الترتيب بالسحب تحتاج ارتفاعاً، والورقة
// فوق الخريطة تصارع إيماءة السحب نفسها — جرّبناها فكان سحب المحطة يحرّك
// الورقة لا المحطة.
//
// أزمنة الوصول من مراحل ڤالهالا لا من قسمة الزمن الكلي: المرحلة داخل
// المدينة أبطأ من مثلها على الطريق الخارجي، والقسمة تكذب على المحطتين.

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';

import '../nav/phrases.dart';
import '../nav/route_model.dart';
import '../state/app_state.dart';
import 'search_screen.dart';
import 'theme.dart';

class TripPlannerScreen extends StatelessWidget {
  const TripPlannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final route = app.proposed;

    return Scaffold(
      backgroundColor: D.bg,
      body: SafeArea(
        child: Column(
          children: [
            const _Header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                children: [
                  const _Endpoints(),
                  const SizedBox(height: 12),
                  if (route != null) _Preview(route: route),
                  const SizedBox(height: 12),
                  const _Summary(),
                  const SizedBox(height: 10),
                  const _StopList(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: DBigButton(
                label: 'تأكيد المسار',
                subtitle: app.routing
                    ? 'نحسب…'
                    : route == null
                        ? 'ما في مسار بعد'
                        : '${durationLabel(route.effectiveTimeS)}'
                            ' · ${hd(route.lengthKm.toStringAsFixed(1))} كم',
                icon: Icons.near_me,
                onTap: route == null || app.routing
                    ? null
                    : () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('تخطيط الرحلة', style: D.h1),
                  Text('عدة محطات .. بمسار واحد', style: D.caption),
                ],
              ),
            ),
            const SizedBox(width: 10),
            DMapButton(
              icon: Icons.arrow_forward,
              tooltip: 'رجوع',
              onTap: () => Navigator.of(context).pop(),
              size: 42,
            ),
          ],
        ),
      );
}

/// «من» و«إلى» وزرّ إضافة محطة.
class _Endpoints extends StatelessWidget {
  const _Endpoints();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Column(
      children: [
        _EndpointRow(
          label: 'من',
          value: 'موقعك الحالي',
          icon: Icons.my_location,
          dim: app.fix == null,
        ),
        const SizedBox(height: 8),
        _EndpointRow(
          label: 'إلى',
          value: app.destination?.title ?? 'اختر وجهة',
          icon: Icons.place,
          dim: app.destination == null,
        ),
        const SizedBox(height: 8),
        DCard(
          radius: D.rInner,
          color: D.cardInner,
          shadow: const [],
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          onTap: app.stops.length >= AppState.maxStops
              ? null
              : () async {
                  final chosen = await Navigator.of(context)
                      .push<Destination>(MaterialPageRoute(
                          builder: (_) => const SearchScreen()));
                  if (chosen != null) await app.addStop(chosen);
                },
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('إضافة محطة',
                        style: D.body.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      app.stops.length >= AppState.maxStops
                          ? 'بلغت أقصى عدد محطات'
                          : 'مثل: الجادرية، الكاظمية …',
                      style: D.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const DIconCircle(Icons.add, size: 36, foreground: D.greenDeep),
            ],
          ),
        ),
      ],
    );
  }
}

class _EndpointRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool dim;

  const _EndpointRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.dim,
  });

  @override
  Widget build(BuildContext context) => DCard(
        radius: D.rInner,
        shadow: D.shadowSoft,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(label, style: D.caption),
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: D.body.copyWith(
                          fontWeight: FontWeight.w700,
                          color: dim ? D.textFaint : D.text)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            DIconCircle(icon, size: 36, foreground: D.greenDeep),
          ],
        ),
      );
}

/// معاينة الخط ومحطّاته مرقّمة.
class _Preview extends StatelessWidget {
  final NavRoute route;
  const _Preview({required this.route});

  @override
  Widget build(BuildContext context) {
    // نقاط المحطات = نهاية كل مرحلة ما عدا الأخيرة (وهي الوجهة)
    final stopPoints = <LatLng>[
      for (var i = 0; i < route.legs.length - 1; i++)
        if (route.legs[i].endShapeIndex < route.shape.length)
          route.shape[route.legs[i].endShapeIndex],
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(D.rCard),
      child: Container(
        height: 190,
        color: D.mintPale,
        child: CustomPaint(
          painter: _PlanPainter(route.shape, stopPoints),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _PlanPainter extends CustomPainter {
  final List<LatLng> shape;
  final List<LatLng> stops;

  _PlanPainter(this.shape, this.stops);

  @override
  void paint(Canvas canvas, Size size) {
    if (shape.length < 2) return;

    var minLat = shape.first.latitude, maxLat = minLat;
    var minLon = shape.first.longitude, maxLon = minLon;
    for (final p in shape) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    const pad = 26.0;
    final spanLat = (maxLat - minLat).abs();
    final spanLon = (maxLon - minLon).abs();
    final scale = [
      spanLon > 0 ? (size.width - pad * 2) / spanLon : double.infinity,
      spanLat > 0 ? (size.height - pad * 2) / spanLat : double.infinity,
    ].reduce((a, b) => a < b ? a : b);
    if (!scale.isFinite) return;

    Offset at(LatLng p) => Offset(
          size.width / 2 + (p.longitude - (minLon + maxLon) / 2) * scale,
          size.height / 2 - (p.latitude - (minLat + maxLat) / 2) * scale,
        );

    final path = Path()..moveTo(at(shape.first).dx, at(shape.first).dy);
    final step = (shape.length / 300).ceil();
    for (var i = step; i < shape.length; i += step) {
      path.lineTo(at(shape[i]).dx, at(shape[i]).dy);
    }
    path.lineTo(at(shape.last).dx, at(shape.last).dy);

    canvas.drawPath(
      path,
      Paint()
        ..color = D.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawCircle(at(shape.first), 7, Paint()..color = D.greenDeep);
    canvas.drawCircle(at(shape.first), 3, Paint()..color = Colors.white);

    for (var i = 0; i < stops.length; i++) {
      _marker(canvas, at(stops[i]), '${i + 1}');
    }
    _marker(canvas, at(shape.last), '${stops.length + 1}');
  }

  void _marker(Canvas canvas, Offset c, String n) {
    canvas.drawCircle(c, 12, Paint()..color = D.ink);
    final tp = TextPainter(
      text: TextSpan(
        text: hd(n),
        style: const TextStyle(
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.rtl,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_PlanPainter old) =>
      old.shape != shape || old.stops != stops;
}

class _Summary extends StatelessWidget {
  const _Summary();

  @override
  Widget build(BuildContext context) {
    final route = context.watch<AppState>().proposed;
    if (route == null) return const SizedBox.shrink();

    return DCard(
      radius: D.rInner,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: _Stat(
              label: 'المسافة',
              value: '${hd(route.lengthKm.toStringAsFixed(1))} كم',
              icon: Icons.straighten,
            ),
          ),
          Container(width: 1, height: 34, color: D.divider),
          Expanded(
            child: _Stat(
              label: 'المدة الكلية',
              value: durationLabel(route.effectiveTimeS),
              icon: Icons.schedule,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _Stat({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(label, style: D.caption),
              Text(value, style: D.h3),
            ],
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 20, color: D.textSoft),
        ],
      );
}

/// قائمة المحطات بترتيب المرور، تُعاد بالسحب.
class _StopList extends StatelessWidget {
  const _StopList();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final route = app.proposed;

    if (app.stops.isEmpty) {
      return DCard(
        radius: D.rInner,
        color: D.cardInner,
        shadow: const [],
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        child: Text(
          'ما في محطات. أضف محطة وتصير الرحلة مرحلتين بمسار واحد بدل '
          'رحلتين منفصلتين.',
          textAlign: TextAlign.center,
          style: D.bodySoft,
        ),
      );
    }

    // وقت الوصول لكل محطة = الآن + مجموع أزمنة المراحل التي تسبقها
    final now = DateTime.now();
    var acc = 0.0;
    final arrivals = <DateTime>[];
    final legKm = <double>[];
    for (var i = 0; i < app.stops.length; i++) {
      final leg = route != null && i < route.legs.length ? route.legs[i] : null;
      acc += leg?.timeS ?? 0;
      arrivals.add(now.add(Duration(seconds: acc.round())));
      legKm.add(leg?.lengthKm ?? 0);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DSectionHeader(
          title: 'ترتيب المحطات',
          subtitle: 'اسحب لإعادة الترتيب',
          icon: Icons.swap_vert,
        ),
        const SizedBox(height: 8),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: app.stops.length,
          // onReorderItem لا onReorder: الأخيرة تعطي فهرساً قبل الحذف
          // فيحتاج تصحيحاً يدوياً، وهي مهجورة أصلاً
          onReorderItem: app.reorderStops,
          itemBuilder: (_, i) => Padding(
            key: ValueKey('stop-$i-${app.stops[i].title}'),
            padding: const EdgeInsets.only(bottom: 8),
            child: _StopRow(
              index: i,
              title: app.stops[i].title,
              arrival: route == null ? null : arrivals[i],
              km: route == null ? null : legKm[i],
              onRemove: () => app.removeStop(i),
            ),
          ),
        ),
      ],
    );
  }
}

class _StopRow extends StatelessWidget {
  final int index;
  final String title;
  final DateTime? arrival;
  final double? km;
  final VoidCallback onRemove;

  const _StopRow({
    required this.index,
    required this.title,
    required this.arrival,
    required this.km,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => DCard(
        radius: D.rInner,
        color: D.cardInner,
        shadow: const [],
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.drag_indicator, color: D.textFaint),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration:
                  const BoxDecoration(color: D.mint, shape: BoxShape.circle),
              child: Text(hd('${index + 1}'),
                  style: D.caption.copyWith(
                      fontWeight: FontWeight.w800, color: D.greenDeep)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: D.body.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (arrival != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(arrivalLabel(arrival!), style: D.bodySoft),
                  Text('${hd(km!.toStringAsFixed(1))} كم', style: D.caption),
                ],
              ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline, color: D.textSoft),
              tooltip: 'احذف المحطة',
            ),
          ],
        ),
      );
}
