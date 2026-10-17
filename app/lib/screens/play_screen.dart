import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/api.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/audio_clip.dart';
import '../widgets/cinema.dart';
import '../widgets/common.dart';
import '../widgets/formats.dart';
import '../widgets/trailer.dart';
import 'result_screen.dart';

class PlayScreen extends StatefulWidget {
  final int jokersLeft;
  final VoidCallback onOpenRankings;
  const PlayScreen({super.key, required this.jokersLeft, required this.onOpenRankings});

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

enum _Feedback { none, correct, partial, wrong, timeout }

class _PlayScreenState extends State<PlayScreen> {
  final _api = AppState.instance.api;
  Question? _q;
  int _totalPoints = 0;
  late int _jokersLeft = widget.jokersLeft;
  bool _busy = false;
  Object? _error;

  Timer? _ticker;
  DateTime? _deadline;
  int _remainingMs = 0;

  int? _selected;
  List<int> _order = [];
  List<int> _removed = [];
  _Feedback _feedback = _Feedback.none;
  int _lastPoints = 0;
  final List<AnswerSummary> _results = [];

  @override
  void initState() {
    super.initState();
    _next();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _next() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _api.nextQuestion();
      if (!mounted) return;
      if (r['finished'] == true) {
        _goToResult();
        return;
      }
      final q = Question.fromJson(asMap(r['question']));
      _jokersLeft = asInt(r['jokers_left'], _jokersLeft);
      _totalPoints = asInt(r['total_points'], _totalPoints);
      setState(() {
        _q = q;
        _selected = null;
        _feedback = _Feedback.none;
        _removed = List.of(q.removedOptions);
        _order = List.generate(q.options.length, (i) => i);
        _remainingMs = q.remainingMs;
        _deadline = DateTime.now().add(Duration(milliseconds: q.remainingMs));
      });
      _startTicker();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _deadline == null) return;
      final left = _deadline!.difference(DateTime.now()).inMilliseconds;
      setState(() => _remainingMs = left < 0 ? 0 : left);
      if (left <= 0 && _feedback == _Feedback.none && !_busy) {
        _submit(null);
      }
    });
  }

  Future<void> _submit(Object? answer) async {
    final q = _q;
    if (q == null || _busy || _feedback != _Feedback.none) return;
    _ticker?.cancel();
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      final r = await _api.submitAnswer(q.position, answer);
      if (!mounted) return;
      _totalPoints = asInt(r['total_points'], _totalPoints);
      final fb = r['timeout'] == true || answer == null
          ? _Feedback.timeout
          : (r['correct'] == true
              ? _Feedback.correct
              : (r['partial'] == true ? _Feedback.partial : _Feedback.wrong));
      if (fb == _Feedback.correct) {
        HapticFeedback.lightImpact();
      } else {
        HapticFeedback.heavyImpact();
      }
      setState(() {
        _lastPoints = asInt(r['points']);
        _results.add(AnswerSummary.fromJson({
          'position': q.position,
          'correct': r['correct'],
          'points': r['points'],
        }));
        _feedback = fb;
      });
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      if (!mounted) return;
      setState(() => _busy = false);
      if (r['finished'] == true) {
        _goToResult();
      } else {
        _next();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e;
        });
      }
    }
  }

  Future<void> _useJoker() async {
    final q = _q;
    if (q == null || _busy) return;
    HapticFeedback.mediumImpact();
    try {
      final r = await _api.useJoker(q.position);
      if (!mounted) return;
      setState(() {
        _removed = ((r['removed_options'] ?? []) as List).map((e) => asInt(e)).toList();
        _jokersLeft = asInt(r['jokers_left'], _jokersLeft - 1);
      });
    } on ApiError catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  void _goToResult() {
    _ticker?.cancel();
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ResultScreen(justFinished: true, onOpenRankings: widget.onOpenRankings),
    ));
  }

  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('leave_game_title')),
        content: Text(tr('leave_game_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('stay'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('leave'))),
        ],
      ),
    );
    return leave == true;
  }

  Future<void> _report() async {
    final q = _q;
    if (q == null) return;
    final ctrl = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('report')),
        content: TextField(
          controller: ctrl,
          maxLength: 300,
          maxLines: 3,
          decoration: InputDecoration(hintText: tr('report_hint')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('send'))),
        ],
      ),
    );
    if (send == true && ctrl.text.trim().isNotEmpty) {
      try {
        await _api.reportQuestion(q.id, ctrl.text.trim());
        if (mounted) showSnack(context, tr('report_sent'));
      } on ApiError catch (e) {
        if (mounted) showSnack(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave()) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(q == null ? tr('loading') : tr('question_n', {'n': q.position + 1})),
          actions: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text('$_totalPoints ${tr('pts')}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.amber)),
              ),
            ),
            IconButton(
              tooltip: tr('report'),
              icon: const Icon(Icons.flag_outlined, size: 20, color: AppColors.textMuted),
              onPressed: q == null ? null : _report,
            ),
          ],
        ),
        body: SafeArea(child: _body(q)),
      ),
    );
  }

  Widget _body(Question? q) {
    if (_error != null && q == null) {
      return ErrorView(message: tr('error_generic'), onRetry: _next);
    }
    if (q == null) return const Center(child: CircularProgressIndicator());
    final fraction = q.timeLimitMs == 0 ? 0.0 : _remainingMs / q.timeLimitMs;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
          children: [
            FilmStrip(current: q.position, answers: _results),
            const SizedBox(height: 12),
            TimerBar(fraction),
            const SizedBox(height: 16),
            Row(
              children: [
                DifficultyBadge(q.difficulty, points: q.maxPoints),
                if (q.speed) ...[
                  const SizedBox(width: 8),
                  SpeedChip(q: q, remainingMs: _remainingMs),
                ],
                const Spacer(),
                if (q.jokerAllowed)
                  TextButton.icon(
                    onPressed: _jokersLeft > 0 && _removed.isEmpty && _feedback == _Feedback.none
                        ? _useJoker
                        : null,
                    icon: const Icon(Icons.contrast_rounded, size: 18),
                    label: Text('${tr('joker')} ($_jokersLeft)'),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (q.imageUrl != null) _QuestionImage(q: q, fraction: fraction),
            if (q.format == 'video' && q.extra['youtube'] is String)
              TrailerClip(
                key: ValueKey('video-${q.id}'),
                videoId: q.extra['youtube'] as String,
                startS: asInt(q.extra['start']),
                endS: asInt(q.extra['end']),
                stop: _feedback != _Feedback.none,
              ),
            if (q.clues.isNotEmpty) ProgressiveClues(q: q, remainingMs: _remainingMs),
            if (q.audioUrl != null)
              AudioClip(
                key: ValueKey('audio-${q.id}'),
                url: q.audioUrl!,
                startMs: q.mediaStartMs,
                attribution: q.audioAttribution,
                stop: _feedback != _Feedback.none,
              ),
            if (q.emojiLine != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(q.emojiLine!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 48, letterSpacing: 6)),
              ),
              Text(
                Strings.pick(q.prompt).split('\n').skip(1).join('\n'),
                style: const TextStyle(
                    fontSize: 21, fontWeight: FontWeight.w800, height: 1.3, letterSpacing: -0.2),
              ),
            ] else
              Text(
                Strings.pick(q.prompt),
                style: const TextStyle(
                    fontSize: 21, fontWeight: FontWeight.w800, height: 1.3, letterSpacing: -0.2),
              ),
            const SizedBox(height: 20),
            _answerArea(q),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton(onPressed: _next, child: Text(tr('retry'))),
              ),
          ],
        ),
        if (_feedback != _Feedback.none) _FeedbackOverlay(_feedback, _lastPoints),
      ],
    );
  }

  Verdict get _verdict => switch (_feedback) {
        _Feedback.correct => Verdict.correct,
        _Feedback.partial => Verdict.partial,
        _Feedback.wrong || _Feedback.timeout => Verdict.wrong,
        _Feedback.none => Verdict.none,
      };

  Widget _answerArea(Question q) {
    final locked = _feedback != _Feedback.none || _busy;
    void submit(Object a) => _submit(a);
    final key = ValueKey('q-${q.id}');
    switch (q.format) {
      case 'order':
        return _orderOptions(q);
      case 'year_slider':
        return YearSliderAnswer(key: key, q: q, locked: locked, onSubmit: submit);
      case 'map':
        return MapAnswer(key: key, q: q, locked: locked, onSubmit: submit);
      case 'match':
        return MatchAnswer(key: key, q: q, locked: locked, onSubmit: submit);
      case 'burst':
        return BurstAnswer(key: key, q: q, locked: locked, onSubmit: submit);
      case 'typed_title':
        return TypedTitleAnswer(key: key, q: q, locked: locked, onSubmit: submit);
      case 'pick_two':
        return PickTwoAnswer(key: key, q: q, locked: locked, onSubmit: submit);
      case 'versus':
        return VersusAnswer(
          key: key,
          q: q,
          selected: _selected,
          verdict: _verdict,
          locked: locked,
          onTap: (i) {
            setState(() => _selected = i);
            _submit(i);
          },
        );
      case 'odd_images':
        return OddImagesAnswer(
          key: key,
          q: q,
          selected: _selected,
          verdict: _verdict,
          removed: _removed,
          locked: locked,
          onTap: (i) {
            setState(() => _selected = i);
            _submit(i);
          },
        );
      default:
        return _choiceOptions(q);
    }
  }

  Widget _choiceOptions(Question q) {
    const letters = ['A', 'B', 'C', 'D', 'E', 'F'];
    return Column(
      children: [
        for (var i = 0; i < q.options.length; i++)
          OptionButton(
            letter: letters[i],
            label: Strings.pick(q.options[i]),
            state: _removed.contains(i)
                ? OptionState.removed
                : _selected == i
                    ? switch (_feedback) {
                        _Feedback.correct => OptionState.correct,
                        _Feedback.partial ||
                        _Feedback.wrong ||
                        _Feedback.timeout =>
                          OptionState.wrong,
                        _Feedback.none => OptionState.selected,
                      }
                    : (_selected != null || _busy ? OptionState.disabled : OptionState.idle),
            onTap: () {
              setState(() => _selected = i);
              _submit(i);
            },
          ),
      ],
    );
  }

  Widget _orderOptions(Question q) {
    final locked = _feedback != _Feedback.none || _busy;
    final border = switch (_feedback) {
      _Feedback.correct => AppColors.success,
      _Feedback.partial => AppColors.amber,
      _Feedback.wrong || _Feedback.timeout => AppColors.error,
      _Feedback.none => AppColors.border,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('drag_to_order'), style: const TextStyle(color: AppColors.textMuted)),
        const SizedBox(height: 10),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: !locked,
          onReorderItem: (oldIndex, newIndex) {
            if (locked) return;
            setState(() {
              final item = _order.removeAt(oldIndex);
              _order.insert(newIndex, item);
            });
          },
          children: [
            for (var pos = 0; pos < _order.length; pos++)
              Container(
                key: ValueKey(_order[pos]),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border, width: 1.5),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.surfaceHigh,
                    child: Text('${pos + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  title: Text(Strings.pick(q.options[_order[pos]]),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: locked ? null : const Icon(Icons.drag_handle_rounded),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: locked ? null : () => _submit(List<int>.of(_order)),
          child: Text(tr('confirm_order')),
        ),
      ],
    );
  }
}

class _QuestionImage extends StatelessWidget {
  final Question q;
  final double fraction;
  const _QuestionImage({required this.q, required this.fraction});

  @override
  Widget build(BuildContext context) {
    final Widget img = q.format == 'image_reveal'
        ? RevealImage(url: q.imageUrl!, mode: q.revealMode, fraction: fraction)
        : ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: Image.network(
              q.imageUrl!,
              width: double.infinity,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) => const SizedBox.shrink(),
            ),
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF07090D),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: ClipRRect(borderRadius: BorderRadius.circular(15), child: img),
          ),
          if (q.imageAttribution != null && q.imageAttribution!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(q.imageAttribution!,
                  style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
            ),
        ],
      ),
    );
  }
}

class _FeedbackOverlay extends StatelessWidget {
  final _Feedback feedback;
  final int points;
  const _FeedbackOverlay(this.feedback, this.points);

  @override
  Widget build(BuildContext context) {
    final (text, color, icon) = switch (feedback) {
      _Feedback.correct => ('${tr('correct')} +$points', AppColors.success, Icons.check_circle_rounded),
      _Feedback.partial => ('${tr('almost')} +$points', AppColors.amber, Icons.star_half_rounded),
      _Feedback.timeout => (tr('timeout'), AppColors.amber, Icons.timer_off_rounded),
      _ => (tr('wrong'), AppColors.error, Icons.cancel_rounded),
    };
    return IgnorePointer(
      child: Stack(children: [
        if (feedback == _Feedback.correct) const Positioned.fill(child: ConfettiBurst()),
        Align(
        alignment: Alignment.center,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.85, end: 1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color, width: 2),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 30),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 34),
                const SizedBox(width: 12),
                Text(text.toUpperCase(), style: AppFonts.marquee(34, color: color, spacing: 1.5)),
              ],
            ),
          ),
        ),
      ),
      ]),
    );
  }
}
