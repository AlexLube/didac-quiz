import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Soluciones del reto de ayer (ya cerrado para todo el mundo).
class SolutionsScreen extends StatefulWidget {
  const SolutionsScreen({super.key});

  @override
  State<SolutionsScreen> createState() => _SolutionsScreenState();
}

class _SolutionsScreenState extends State<SolutionsScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await AppState.instance.api.solutions();
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('yesterday_solutions'))),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(message: tr('error_generic'), onRetry: _load);
    final d = _data;
    if (d == null) return Center(child: Text(tr('no_challenge')));
    final questions = asMapList(d['questions']);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: questions.length,
      separatorBuilder: (_, i) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _SolutionCard(questions[i]),
    );
  }
}

class _SolutionCard extends StatelessWidget {
  final Map<String, dynamic> q;
  const _SolutionCard(this.q);

  @override
  Widget build(BuildContext context) {
    final options = (q['options'] as List);
    final answer = q['answer'];
    final myCorrect = q['my_correct'] as bool?;
    final accuracy = q['accuracy'];
    String answerText;
    if (answer is List) {
      answerText = answer.map((i) => Strings.pick(options[asInt(i)])).join('  →  ');
    } else {
      answerText = Strings.pick(options[asInt(answer)]);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${asInt(q['position']) + 1}.',
                    style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.amber)),
                const SizedBox(width: 8),
                DifficultyBadge(asInt(q['difficulty'], 1)),
                const Spacer(),
                if (myCorrect != null)
                  Icon(myCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: myCorrect ? AppColors.success : AppColors.error),
              ],
            ),
            const SizedBox(height: 10),
            if (q['image_url'] != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network('${q['image_url']}',
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => const SizedBox.shrink()),
              ),
              if (q['image_attribution'] != null)
                Text('${q['image_attribution']}',
                    style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
              const SizedBox(height: 8),
            ],
            if (q['audio_attribution'] != null)
              Text('🎵 ${q['audio_attribution']}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            Text(Strings.pick(q['prompt']),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('✔ $answerText',
                style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700)),
            if (q['explanation'] != null) ...[
              const SizedBox(height: 8),
              Text(Strings.pick(q['explanation']), style: const TextStyle(color: AppColors.textMuted)),
            ],
            if (accuracy != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('${((accuracy as num) * 100).round()}% ✔',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}
