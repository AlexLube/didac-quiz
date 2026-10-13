import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../strings.dart';
import '../theme.dart';

/// Estado visual de un resultado ya enviado, para colorear las respuestas.
enum Verdict { none, correct, partial, wrong }

Color verdictColor(Verdict v) => switch (v) {
      Verdict.correct => AppColors.success,
      Verdict.partial => AppColors.amber,
      Verdict.wrong => AppColors.error,
      Verdict.none => AppColors.surfaceHigh,
    };

/// Puntos que valdría ahora una respuesta correcta en una pregunta "de rapidez"
/// (igual que en el servidor: se pierde 1 punto cada tercio del tiempo, mínimo 1).
int speedPointsNow(Question q, int remainingMs) {
  final elapsed = (q.timeLimitMs - remainingMs).clamp(0, q.timeLimitMs);
  final lost = (3 * elapsed / (q.timeLimitMs == 0 ? 1 : q.timeLimitMs)).floor().clamp(0, 2);
  final p = q.maxPoints - lost;
  return p < 1 ? 1 : p;
}

// ---------------------------------------------------------------------------
// Año con slider
// ---------------------------------------------------------------------------
class YearSliderAnswer extends StatefulWidget {
  final Question q;
  final bool locked;
  final void Function(Object answer) onSubmit;
  const YearSliderAnswer({super.key, required this.q, required this.locked, required this.onSubmit});

  @override
  State<YearSliderAnswer> createState() => _YearSliderAnswerState();
}

class _YearSliderAnswerState extends State<YearSliderAnswer> {
  late final int _min = asInt(widget.q.extra['min'], 1920);
  late final int _max = asInt(widget.q.extra['max'], 2025);
  late double _value = ((_min + _max) / 2).roundToDouble();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border, width: 2),
          ),
          child: Column(
            children: [
              Text('${_value.round()}',
                  style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: AppColors.accent)),
              Slider(
                value: _value,
                min: _min.toDouble(),
                max: _max.toDouble(),
                divisions: _max - _min,
                activeColor: AppColors.accent,
                onChanged: widget.locked ? null : (v) => setState(() => _value = v.roundToDouble()),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$_min', style: const TextStyle(color: AppColors.textMuted)),
                    Text('$_max', style: const TextStyle(color: AppColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(tr('slider_hint'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: widget.locked ? null : () => widget.onSubmit(_value.round()),
          child: Text(tr('confirm')),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Mapa: toca dónde se rodó
// ---------------------------------------------------------------------------
class MapAnswer extends StatefulWidget {
  final Question q;
  final bool locked;
  final void Function(Object answer) onSubmit;
  const MapAnswer({super.key, required this.q, required this.locked, required this.onSubmit});

  @override
  State<MapAnswer> createState() => _MapAnswerState();
}

class _MapAnswerState extends State<MapAnswer> {
  final _controller = TransformationController();
  Offset? _pick; // fracciones (0..1) dentro del mapa: x = longitud, y = latitud
  bool _centered = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final viewW = c.maxWidth;
      final viewH = viewW * 0.8;
      final mapW = viewW * 1.6;
      if (!_centered) {
        _centered = true;
        _controller.value = Matrix4.translationValues(-(mapW - viewW) * 0.47, 0, 0);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Container(
              height: viewH,
              decoration: BoxDecoration(border: Border.all(color: AppColors.border, width: 2)),
              child: InteractiveViewer(
                transformationController: _controller,
                constrained: false,
                minScale: 1,
                maxScale: 8,
                child: GestureDetector(
                  onTapUp: widget.locked
                      ? null
                      : (d) => setState(() => _pick = Offset(
                            (d.localPosition.dx / mapW).clamp(0.0, 1.0),
                            (d.localPosition.dy / viewH).clamp(0.0, 1.0),
                          )),
                  child: SizedBox(
                    width: mapW,
                    height: viewH,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Image.asset('assets/world_map.png', fit: BoxFit.fill),
                        ),
                        if (_pick != null)
                          Positioned(
                            left: _pick!.dx * mapW - 14,
                            top: _pick!.dy * viewH - 28,
                            child: const Icon(Icons.location_on_rounded, size: 28, color: AppColors.accent),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(tr('map_hint'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: widget.locked || _pick == null
                ? null
                : () => widget.onSubmit({
                      'lon': double.parse((_pick!.dx * 360 - 180).toStringAsFixed(3)),
                      'lat': double.parse((90 - _pick!.dy * 180).toStringAsFixed(3)),
                    }),
            child: Text(tr('confirm')),
          ),
        ],
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Emparejar (arrastrar o tocar)
// ---------------------------------------------------------------------------
class MatchAnswer extends StatefulWidget {
  final Question q;
  final bool locked;
  final void Function(Object answer) onSubmit;
  const MatchAnswer({super.key, required this.q, required this.locked, required this.onSubmit});

  @override
  State<MatchAnswer> createState() => _MatchAnswerState();
}

class _MatchAnswerState extends State<MatchAnswer> {
  late final List<dynamic> _rights = (widget.q.extra['right'] as List?) ?? const [];
  late final List<int?> _assign = List<int?>.filled(widget.q.options.length, null);
  int? _selected; // chip de la derecha seleccionado para asignar tocando

  void _put(int left, int right) {
    if (widget.locked) return;
    setState(() {
      for (var i = 0; i < _assign.length; i++) {
        if (_assign[i] == right) _assign[i] = null;
      }
      _assign[left] = right;
      _selected = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final used = _assign.whereType<int>().toSet();
    final complete = !_assign.contains(null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var l = 0; l < widget.q.options.length; l++)
          DragTarget<int>(
            onAcceptWithDetails: (d) => _put(l, d.data),
            builder: (context, candidate, rejected) {
              final hovering = candidate.isNotEmpty;
              final r = _assign[l];
              return GestureDetector(
                onTap: widget.locked
                    ? null
                    : () {
                        if (_selected != null) {
                          _put(l, _selected!);
                        } else if (r != null) {
                          setState(() => _assign[l] = null);
                        }
                      },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: hovering ? AppColors.accent : AppColors.border, width: 2),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Text(Strings.pick(widget.q.options[l]),
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                      const Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.textMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 5,
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                          decoration: BoxDecoration(
                            color: r == null ? AppColors.background : AppColors.accent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: r == null ? AppColors.border : AppColors.accent,
                                style: r == null ? BorderStyle.solid : BorderStyle.solid),
                          ),
                          child: Text(
                            r == null ? tr('match_drop') : Strings.pick(_rights[r]),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: r == null ? AppColors.textMuted : AppColors.text),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < _rights.length; i++)
              if (!used.contains(i))
                Draggable<int>(
                  data: i,
                  maxSimultaneousDrags: widget.locked ? 0 : 1,
                  feedback: Material(
                    color: Colors.transparent,
                    child: _chip(Strings.pick(_rights[i]), true),
                  ),
                  childWhenDragging: Opacity(opacity: 0.3, child: _chip(Strings.pick(_rights[i]), false)),
                  child: GestureDetector(
                    onTap: widget.locked ? null : () => setState(() => _selected = _selected == i ? null : i),
                    child: _chip(Strings.pick(_rights[i]), _selected == i),
                  ),
                ),
          ],
        ),
        const SizedBox(height: 8),
        Text(tr('match_hint'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: widget.locked || !complete ? null : () => widget.onSubmit(_assign.cast<int>().toList()),
          child: Text(tr('confirm')),
        ),
      ],
    );
  }

  Widget _chip(String text, bool active) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.accent : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                fontWeight: FontWeight.w800, color: active ? Colors.black : AppColors.text, fontSize: 14)),
      );
}

// ---------------------------------------------------------------------------
// Verdadero / falso en ráfaga
// ---------------------------------------------------------------------------
class BurstAnswer extends StatefulWidget {
  final Question q;
  final bool locked;
  final void Function(Object answer) onSubmit;
  const BurstAnswer({super.key, required this.q, required this.locked, required this.onSubmit});

  @override
  State<BurstAnswer> createState() => _BurstAnswerState();
}

class _BurstAnswerState extends State<BurstAnswer> {
  late final List<bool?> _vals = List<bool?>.filled(widget.q.options.length, null);

  @override
  Widget build(BuildContext context) {
    final complete = !_vals.contains(null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.q.options.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border, width: 2),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(Strings.pick(widget.q.options[i]),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                _tf(i, true),
                const SizedBox(width: 6),
                _tf(i, false),
              ],
            ),
          ),
        const SizedBox(height: 6),
        FilledButton(
          onPressed: widget.locked || !complete ? null : () => widget.onSubmit(_vals.cast<bool>().toList()),
          child: Text(tr('confirm')),
        ),
      ],
    );
  }

  Widget _tf(int i, bool value) {
    final on = _vals[i] == value;
    final color = value ? AppColors.success : AppColors.error;
    return GestureDetector(
      onTap: widget.locked ? null : () => setState(() => _vals[i] = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 52,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? color : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color, width: 2),
        ),
        child: Text(value ? tr('true_short') : tr('false_short'),
            style: TextStyle(fontWeight: FontWeight.w900, color: on ? Colors.black : color)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Escribe el título (con autocompletado)
// ---------------------------------------------------------------------------
class TypedTitleAnswer extends StatefulWidget {
  final Question q;
  final bool locked;
  final void Function(Object answer) onSubmit;
  const TypedTitleAnswer({super.key, required this.q, required this.locked, required this.onSubmit});

  @override
  State<TypedTitleAnswer> createState() => _TypedTitleAnswerState();
}

class _TypedTitleAnswerState extends State<TypedTitleAnswer> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _hits = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _changed(String text) {
    setState(() {});
    _debounce?.cancel();
    if (text.trim().length < 2) {
      setState(() => _hits = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final r = await AppState.instance.api.searchTitles(text.trim());
        if (mounted) setState(() => _hits = r);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ctrl,
          enabled: !widget.locked,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: tr('type_title'),
            prefixIcon: const Icon(Icons.movie_filter_rounded),
          ),
          onChanged: _changed,
          onSubmitted: (t) {
            if (t.trim().isNotEmpty && !widget.locked) widget.onSubmit(t.trim());
          },
        ),
        const SizedBox(height: 8),
        if (!widget.locked)
          for (final h in _hits.take(5))
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: ListTile(
                dense: true,
                title: Text('${h['title']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                trailing: Text('${h['year'] ?? ''}', style: const TextStyle(color: AppColors.textMuted)),
                onTap: () {
                  _ctrl.text = '${h['title']}';
                  setState(() => _hits = []);
                },
              ),
            ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: widget.locked || _ctrl.text.trim().isEmpty ? null : () => widget.onSubmit(_ctrl.text.trim()),
          child: Text(tr('confirm')),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Elige dos de cinco
// ---------------------------------------------------------------------------
class PickTwoAnswer extends StatefulWidget {
  final Question q;
  final bool locked;
  final void Function(Object answer) onSubmit;
  const PickTwoAnswer({super.key, required this.q, required this.locked, required this.onSubmit});

  @override
  State<PickTwoAnswer> createState() => _PickTwoAnswerState();
}

class _PickTwoAnswerState extends State<PickTwoAnswer> {
  final Set<int> _picked = {};

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.q.options.length; i++)
          GestureDetector(
            onTap: widget.locked
                ? null
                : () => setState(() {
                      if (!_picked.remove(i) && _picked.length < 2) _picked.add(i);
                    }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              decoration: BoxDecoration(
                color: _picked.contains(i) ? AppColors.accent.withValues(alpha: 0.16) : AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _picked.contains(i) ? AppColors.accent : AppColors.border, width: 2),
              ),
              child: Row(
                children: [
                  Icon(_picked.contains(i) ? Icons.check_circle_rounded : Icons.circle_outlined,
                      color: _picked.contains(i) ? AppColors.accent : AppColors.textMuted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(Strings.pick(widget.q.options[i]),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 4),
        FilledButton(
          onPressed: widget.locked || _picked.length != 2 ? null : () => widget.onSubmit(_picked.toList()..sort()),
          child: Text(tr('confirm')),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Más / menos: dos tarjetas enfrentadas
// ---------------------------------------------------------------------------
class VersusAnswer extends StatelessWidget {
  final Question q;
  final int? selected;
  final Verdict verdict;
  final bool locked;
  final void Function(int index) onTap;
  const VersusAnswer(
      {super.key,
      required this.q,
      required this.selected,
      required this.verdict,
      required this.locked,
      required this.onTap});

  Widget _card(int i) {
    final isSel = selected == i;
    final color = isSel ? verdictColor(verdict == Verdict.none ? Verdict.partial : verdict) : AppColors.border;
    return GestureDetector(
      onTap: locked ? null : () => onTap(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
        decoration: BoxDecoration(
          color: isSel ? color.withValues(alpha: 0.18) : AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color, width: 3),
        ),
        child: Text(Strings.pick(q.options[i]),
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _card(0),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.accent,
            child: const Text('VS', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black)),
          ),
        ),
        _card(1),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Intruso entre cuatro fotos
// ---------------------------------------------------------------------------
class OddImagesAnswer extends StatelessWidget {
  final Question q;
  final int? selected;
  final Verdict verdict;
  final List<int> removed;
  final bool locked;
  final void Function(int index) onTap;
  const OddImagesAnswer(
      {super.key,
      required this.q,
      required this.selected,
      required this.verdict,
      required this.removed,
      required this.locked,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.15,
      children: [
        for (var i = 0; i < q.options.length; i++)
          Opacity(
            opacity: removed.contains(i) ? 0.25 : 1,
            child: GestureDetector(
              onTap: locked || removed.contains(i) ? null : () => onTap(i),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: selected == i
                          ? verdictColor(verdict == Verdict.none ? Verdict.partial : verdict)
                          : AppColors.border,
                      width: 3),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        '${(q.options[i] as Map)['image']}',
                        fit: BoxFit.cover,
                        errorBuilder: (context, e, s) => const ColoredBox(color: AppColors.surface),
                      ),
                      Positioned(
                        left: 8,
                        top: 8,
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.black87,
                          child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pistas que aparecen poco a poco
// ---------------------------------------------------------------------------
class ProgressiveClues extends StatelessWidget {
  final Question q;
  final int remainingMs;
  const ProgressiveClues({super.key, required this.q, required this.remainingMs});

  @override
  Widget build(BuildContext context) {
    final elapsed = q.timeLimitMs - remainingMs;
    final reveal = ((q.extra['reveal_ms'] as List?) ?? const []).map((e) => asInt(e)).toList();
    final clues = q.clues;
    var visible = 0;
    for (var i = 0; i < clues.length; i++) {
      if (i >= reveal.length || reveal[i] <= elapsed) visible = i + 1;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < clues.length; i++)
            AnimatedOpacity(
              duration: const Duration(milliseconds: 400),
              opacity: i < visible ? 1 : 0.0,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Text(i < visible ? Strings.pick(clues[i]) : ' ',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Muestra cuánto vale acertar ahora (preguntas de rapidez).
class SpeedChip extends StatelessWidget {
  final Question q;
  final int remainingMs;
  const SpeedChip({super.key, required this.q, required this.remainingMs});

  @override
  Widget build(BuildContext context) {
    final p = speedPointsNow(q, remainingMs);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent, width: 1.5),
      ),
      child: Text(tr('worth_now', {'n': p}),
          style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.accent, fontSize: 13)),
    );
  }
}

// ---------------------------------------------------------------------------
// Imagen que se va revelando (desenfoque, pixelado o zoom)
// ---------------------------------------------------------------------------
class RevealImage extends StatelessWidget {
  final String url;
  final String mode; // blur | pixel | zoom
  final double fraction; // 1 = al empezar (muy oculta), 0 = tiempo agotado (nítida)
  const RevealImage({super.key, required this.url, required this.mode, required this.fraction});

  @override
  Widget build(BuildContext context) {
    final f = fraction.clamp(0.0, 1.0);
    const h = 220.0;
    switch (mode) {
      case 'pixel':
        const steps = [8, 12, 18, 28, 44, 70, 110, 180];
        final i = ((1 - f) * (steps.length - 1)).round();
        return Image.network(url,
            height: h,
            width: double.infinity,
            fit: BoxFit.cover,
            cacheWidth: steps[i],
            filterQuality: FilterQuality.none,
            errorBuilder: (context, e, s) => const SizedBox(height: h));
      case 'zoom':
        return SizedBox(
          height: h,
          width: double.infinity,
          child: ClipRect(
            child: Transform.scale(
              scale: 1 + 4 * f,
              child: Image.network(url, fit: BoxFit.cover, errorBuilder: (context, e, s) => const SizedBox()),
            ),
          ),
        );
      default:
        return ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 18.0 * f, sigmaY: 18.0 * f),
          child: Image.network(url,
              height: h,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, e, s) => const SizedBox(height: h)),
        );
    }
  }
}
