import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/api.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'result_screen.dart';

class PlayScreen extends StatefulWidget {
  final int jokersLeft;
  final VoidCallback onOpenRankings;
  const PlayScreen({super.key, required this.jokersLeft, required this.onOpenRankings});

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

enum _Feedback { none, correct, wrong, timeout }

class _PlayScreenState extends State<PlayScreen> {
  final _api = AppState.instance.api;
  Question? _q;
  int _totalPoints = 0;
  late int _jokersLeft = widget.jokersLeft;
  bool _busy = false;
  Object? _error;

  // Temporizador visual
  Timer? _ticker;
  DateTime? _deadline;
  int _remainingMs = 0;

  // Respuesta en curso
  int? _selected;
  List<int> _order = [];
  List<int> _removed = [];
  _Feedback _feedback = _Feedback.none;

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
    setState(() => _busy = true);
    try {
      final r = await _api.submitAnswer(q.position, answer);
      if (!mounted) return;
      _totalPoints = asInt(r['total_points'], _totalPoints);
      setState(() {
        _feedback = r['timeout'] == true || answer == null
            ? _Feedback.timeout
            : (r['correct'] == true ? _Feedback.correct : _Feedback.wrong);
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
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('$_totalPoints ${tr('pts')}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.amber)),
              ),
            ),
            IconButton(
              tooltip: tr('report'),
              icon: const Icon(Icons.flag_outlined),
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
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _ProgressDots(current: q.position),
            const SizedBox(height: 14),
            TimerBar(fraction),
            const SizedBox(height: 18),
            Row(
              children: [
                DifficultyBadge(q.difficulty),
                const Spacer(),
                if (q.jokerAllowed)
                  TextButton.icon(
                    onPressed: _jokersLeft > 0 && _removed.isEmpty && _feedback == _Feedback.none
                        ? _useJoker
                        : null,
                    icon: const Icon(Icons.contrast_rounded),
                    label: Text('${tr('joker')} ($_jokersLeft)'),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (q.imageUrl != null) _QuestionImage(q: q, fraction: fraction),
            Text(
              Strings.pick(q.prompt),
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, height: 1.25),
            ),
            const SizedBox(height: 22),
            if (q.isOrder) _orderOptions(q) else _choiceOptions(q),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton(onPressed: _next, child: Text(tr('retry'))),
              ),
          ],
        ),
        if (_feedback != _Feedback.none) _FeedbackOverlay(_feedback),
      ],
    );
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
                        _Feedback.wrong || _Feedback.timeout => OptionState.wrong,
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
      _Feedback.wrong || _Feedback.timeout => AppColors.error,
      _Feedback.none => AppColors.surfaceHigh,
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
                  border: Border.all(color: border, width: 2),
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

class _ProgressDots extends StatelessWidget {
  final int current;
  const _ProgressDots({required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 10; i++)
          Expanded(
            child: Container(
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: i < current
                    ? AppColors.amber
                    : (i == current ? AppColors.text : AppColors.surfaceHigh),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
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
    Widget img = Image.network(
      q.imageUrl!,
      height: 200,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stack) => const SizedBox.shrink(),
    );
    if (q.format == 'image_reveal') {
      // La imagen se va aclarando a medida que pasa el tiempo.
      final sigma = 14.0 * fraction.clamp(0.0, 1.0);
      img = ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma), child: img);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(18), child: img),
          if (q.imageAttribution != null)
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
  const _FeedbackOverlay(this.feedback);

  @override
  Widget build(BuildContext context) {
    final (text, color, icon) = switch (feedback) {
      _Feedback.correct => (tr('correct'), AppColors.success, Icons.check_circle_rounded),
      _Feedback.timeout => (tr('timeout'), AppColors.amber, Icons.timer_off_rounded),
      _ => (tr('wrong'), AppColors.error, Icons.cancel_rounded),
    };
    return IgnorePointer(
      child: Align(
        alignment: Alignment.center,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1),
          duration: const Duration(milliseconds: 350),
          curve: Curves.elasticOut,
          builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: color, width: 3),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 36),
                const SizedBox(width: 12),
                Text(text, style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
