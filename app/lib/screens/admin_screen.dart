import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../services/api.dart';
import '../theme.dart';

/// Administración de DidacCine Quiz: solo la ven las cuentas registradas como administradoras.
class AdminScreen extends StatelessWidget {
  final Api api;
  const AdminScreen({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Administración'),
          bottom: const TabBar(
            indicatorColor: AppColors.accent,
            tabs: [Tab(text: 'Panel'), Tab(text: 'Preguntas'), Tab(text: 'Retos')],
          ),
        ),
        body: TabBarView(children: [
          _DashboardTab(api: api),
          _QuestionsTab(api: api),
          _ChallengesTab(api: api),
        ]),
      ),
    );
  }
}

String _txt(dynamic v) {
  if (v is Map) return (v['es'] ?? v['en'] ?? '').toString();
  return (v ?? '').toString();
}

void _toast(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

// ---------------------------------------------------------------------------
class _DashboardTab extends StatefulWidget {
  final Api api;
  const _DashboardTab({required this.api});
  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  late Future<Map<String, dynamic>> _f = widget.api.adminDashboard();

  void _reload() => setState(() => _f = widget.api.adminDashboard());

  Widget _stat(String label, Object? value) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${value ?? '—'}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
              Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _f,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('No se pudo cargar: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final d = snap.data!;
        final u = asMap(d['users']), g = asMap(d['games']), c = asMap(d['challenges']), q = asMap(d['questions']);
        final days = asInt(c['days_left']);
        final reports = asMapList(d['reports']);
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [_stat('registrados', u['registered']), _stat('activos hoy', u['active_today'])]),
            Row(children: [_stat('activos 7 días', u['active_7d']), _stat('activos 30 días', u['active_30d'])]),
            Row(children: [
              _stat('partidas hoy (empezadas)', g['today_started']),
              _stat('terminadas hoy', g['today_finished'])
            ]),
            Row(children: [_stat('partidas totales', g['total']), _stat('media 7 días (pts)', g['avg_points_7d'])]),
            Card(
              color: days < 15 ? AppColors.curtain.withValues(alpha: 0.3) : null,
              child: ListTile(
                leading: const Icon(Icons.event_available_rounded),
                title: Text('$days días de retos preparados'),
                subtitle: Text('Último reto: ${c['last_date'] ?? '—'}'
                    '${days < 15 ? '\nLa rutina mensual generará más el próximo lunes.' : ''}'),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.quiz_rounded),
                title: Text('${q['active']} preguntas activas de ${q['total']}'),
                subtitle: Text('${q['scheduled']} programadas en retos futuros\n'
                    '${asMap(q['by_format']).entries.map((e) => '${e.key}: ${e.value}').join(' · ')}'),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Próximos retos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            for (final r in asMapList(c['upcoming']))
              ListTile(
                dense: true,
                title: Text('${r['date']}  ${_txt(r['title']).isEmpty ? '' : _txt(r['title'])}'),
                subtitle: Text('${r['kind']}'),
              ),
            const SizedBox(height: 8),
            Text('Avisos abiertos (${reports.length})',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            if (reports.isEmpty) const Text('Ninguno.', style: TextStyle(color: AppColors.textMuted)),
            for (final r in reports)
              Card(
                child: ListTile(
                  title: Text(_txt(r['prompt'])),
                  subtitle: Text('Pregunta ${r['question_id']} · ${r['format']} · ${r['reason'] ?? ''}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'Desactivar pregunta y cerrar aviso',
                      icon: const Icon(Icons.block_rounded),
                      onPressed: () async {
                        await widget.api.adminSetActive(asInt(r['question_id']), false);
                        await widget.api.adminResolveReport(asInt(r['id']), 'fixed');
                        _reload();
                      },
                    ),
                    IconButton(
                      tooltip: 'Descartar aviso',
                      icon: const Icon(Icons.check_rounded),
                      onPressed: () async {
                        await widget.api.adminResolveReport(asInt(r['id']), 'dismissed');
                        _reload();
                      },
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: 8),
            const Text('Más falladas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            for (final r in asMapList(d['hardest']))
              ListTile(
                dense: true,
                title: Text(_txt(r['prompt']), maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${r['format']} · ${r['shown']} veces'),
                trailing: Text('${(asDouble(r['accuracy']) * 100).round()} %'),
              ),
          ]),
        );
      },
    );
  }
}

double asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

// ---------------------------------------------------------------------------
class _QuestionsTab extends StatefulWidget {
  final Api api;
  const _QuestionsTab({required this.api});
  @override
  State<_QuestionsTab> createState() => _QuestionsTabState();
}

class _QuestionsTabState extends State<_QuestionsTab> {
  final _search = TextEditingController();
  bool _manual = false;
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() =>
      widget.api.adminQuestions(search: _search.text.trim(), onlyManual: _manual);

  void _reload() => setState(() => _f = _load());

  Future<void> _edit(Map<String, dynamic>? q) async {
    final saved = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => _QuestionEditor(api: widget.api, question: q)));
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(hintText: 'Buscar en enunciados y opciones', isDense: true),
                onSubmitted: (_) => _reload(),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(label: const Text('Propias'), selected: _manual, onSelected: (v) {
              _manual = v;
              _reload();
            }),
          ]),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _f,
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text('No se pudo cargar: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final rows = snap.data!;
              if (rows.isEmpty) return const Center(child: Text('Sin resultados.'));
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final q = rows[i];
                  final active = q['active'] == true;
                  return Card(
                    child: ListTile(
                      leading: q['image_url'] != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(q['image_url'] as String, width: 48, height: 48, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_rounded)))
                          : const Icon(Icons.help_outline_rounded),
                      title: Text(_txt(q['prompt']), maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: active ? null : AppColors.textMuted)),
                      subtitle: Text('#${q['id']} · ${q['format']} · dif. ${q['difficulty']}'
                          ' · ${q['times_shown'] ?? 0} veces${active ? '' : ' · INACTIVA'}'),
                      onTap: () => _edit(q),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _QuestionEditor extends StatefulWidget {
  final Api api;
  final Map<String, dynamic>? question;
  const _QuestionEditor({required this.api, this.question});
  @override
  State<_QuestionEditor> createState() => _QuestionEditorState();
}

class _QuestionEditorState extends State<_QuestionEditor> {
  late final Map<String, dynamic> q = Map.of(widget.question ?? {'format': 'choice', 'difficulty': 2, 'active': true});
  late final bool isNew = widget.question == null;
  late final _promptEs = TextEditingController(text: _txt(q['prompt']));
  late final _promptEn = TextEditingController(text: q['prompt'] is Map ? (q['prompt']['en'] ?? '').toString() : '');
  late final _expEs = TextEditingController(text: _txt(q['explanation']));
  late final _expEn = TextEditingController(text: q['explanation'] is Map ? (q['explanation']['en'] ?? '').toString() : '');
  late final _attr = TextEditingController(text: (q['image_attribution'] ?? '').toString());
  late final List<TextEditingController> _opts = [
    for (var i = 0; i < 4; i++)
      TextEditingController(text: (q['options'] is List && i < (q['options'] as List).length)
          ? _txt((q['options'] as List)[i]) : ''),
  ];
  int _answer = 0;
  bool _busy = false;

  bool get _isChoice => q['format'] == 'choice';

  @override
  void initState() {
    super.initState();
    if (_isChoice && q['answer'] is int) _answer = q['answer'] as int;
  }

  Future<void> _pickImage() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (f == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await f.readAsBytes();
      final ext = f.name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      q['image_url'] = await widget.api.adminUploadImage(bytes, ext);
    } catch (e) {
      if (mounted) _toast(context, 'No se pudo subir la imagen: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    if (_promptEs.text.trim().isEmpty) return _toast(context, 'Escribe el enunciado.');
    final data = Map<String, dynamic>.of(q)..remove('id')..remove('created_at');
    data['prompt'] = {'es': _promptEs.text.trim(), 'en': _promptEn.text.trim().isEmpty ? _promptEs.text.trim() : _promptEn.text.trim()};
    data['explanation'] = {'es': _expEs.text.trim(), 'en': _expEn.text.trim().isEmpty ? _expEs.text.trim() : _expEn.text.trim()};
    data['image_attribution'] = _attr.text.trim();
    if (_isChoice) {
      final opts = _opts.map((c) => c.text.trim()).toList();
      if (opts.any((o) => o.isEmpty)) return _toast(context, 'Rellena las cuatro opciones.');
      data['options'] = [for (final o in opts) {'es': o, 'en': o}];
      data['answer'] = _answer;
    }
    setState(() => _busy = true);
    try {
      await widget.api.adminSaveQuestion(isNew ? null : asInt(q['id']), data);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _toast(context, 'No se pudo guardar: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = q['image_url'] as String?;
    return Scaffold(
      appBar: AppBar(title: Text(isNew ? 'Nueva pregunta' : 'Pregunta #${q['id']}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (!_isChoice)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Formato «${q['format']}»: aquí puedes cambiar textos, imagen, dificultad y estado. '
                  'Las opciones y la respuesta de este formato no se editan desde la app.'),
            ),
          ),
        TextField(controller: _promptEs, decoration: const InputDecoration(labelText: 'Enunciado (español)'), maxLines: 3),
        const SizedBox(height: 10),
        TextField(controller: _promptEn, decoration: const InputDecoration(labelText: 'Enunciado (inglés, opcional)'), maxLines: 3),
        const SizedBox(height: 10),
        if (_isChoice) ...[
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Radio<int>(value: i, groupValue: _answer, onChanged: (v) => setState(() => _answer = v!)),
                Expanded(child: TextField(controller: _opts[i], decoration: InputDecoration(labelText: 'Opción ${i + 1}'))),
              ]),
            ),
          const Text('Marca la opción correcta.', style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 10),
        ],
        TextField(controller: _expEs, decoration: const InputDecoration(labelText: 'Curiosidad (español)'), maxLines: 2),
        const SizedBox(height: 10),
        TextField(controller: _expEn, decoration: const InputDecoration(labelText: 'Curiosidad (inglés, opcional)'), maxLines: 2),
        const SizedBox(height: 14),
        Row(children: [
          const Text('Dificultad'),
          const SizedBox(width: 12),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 1, label: Text('1')),
              ButtonSegment(value: 2, label: Text('2')),
              ButtonSegment(value: 3, label: Text('3')),
            ],
            selected: {asInt(q['difficulty'], 2)},
            onSelectionChanged: (s) => setState(() {
              q['difficulty'] = s.first;
              q['max_points'] = s.first;
            }),
          ),
        ]),
        SwitchListTile(
          title: const Text('Activa'),
          value: q['active'] != false,
          onChanged: (v) => setState(() => q['active'] = v),
        ),
        const SizedBox(height: 6),
        if (img != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(img, height: 180, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Text('No se puede mostrar la imagen')),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _pickImage,
              icon: const Icon(Icons.add_photo_alternate_rounded),
              label: Text(img == null ? 'Subir imagen propia' : 'Cambiar imagen'),
            ),
          ),
          if (img != null)
            IconButton(onPressed: () => setState(() => q['image_url'] = null), icon: const Icon(Icons.delete_outline_rounded)),
        ]),
        const SizedBox(height: 10),
        TextField(controller: _attr, decoration: const InputDecoration(labelText: 'Autoría de la imagen (obligatoria si no es tuya)')),
        const SizedBox(height: 20),
        FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Guardando…' : 'Guardar')),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
class _ChallengesTab extends StatefulWidget {
  final Api api;
  const _ChallengesTab({required this.api});
  @override
  State<_ChallengesTab> createState() => _ChallengesTabState();
}

class _ChallengesTabState extends State<_ChallengesTab> {
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  late Future<Map<String, dynamic>?> _f = widget.api.adminChallenge(_date);

  void _reload() => setState(() => _f = widget.api.adminChallenge(_date));

  Future<void> _pickDate() async {
    final d = await showDatePicker(
        context: context,
        initialDate: _date,
        firstDate: DateTime.now().subtract(const Duration(days: 60)),
        lastDate: DateTime.now().add(const Duration(days: 400)));
    if (d != null) {
      _date = d;
      _reload();
    }
  }

  Future<void> _replace(int position) async {
    final id = await showDialog<int>(context: context, builder: (_) => _QuestionPicker(api: widget.api));
    if (id == null) return;
    try {
      await widget.api.adminReplace(_date, position, id);
      if (mounted) _toast(context, 'Pregunta cambiada.');
      _reload();
    } catch (e) {
      if (mounted) _toast(context, e is ApiError ? 'No se pudo: ${e.code}' : '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
    return ListView(padding: const EdgeInsets.all(16), children: [
      OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.calendar_month_rounded), label: Text('Reto del $label')),
      const SizedBox(height: 8),
      FutureBuilder<Map<String, dynamic>?>(
        future: _f,
        builder: (context, snap) {
          if (snap.hasError) return Text('No se pudo cargar: ${snap.error}');
          if (!snap.hasData && snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final ch = snap.data;
          if (ch == null) return const Text('No hay reto programado ese día.');
          final editable = ch['editable'] == true;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${ch['kind']}${_txt(ch['title']).isEmpty ? '' : ' · ${_txt(ch['title'])}'}',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            if (!editable) const Text('Este reto ya está abierto: no se puede cambiar.', style: TextStyle(color: AppColors.textMuted)),
            for (final q in asMapList(ch['questions']))
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text('${asInt(q['position']) + 1}')),
                  title: Text(_txt(q['prompt']), maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text('#${q['id']} · ${q['format']} · hasta ${q['max_points']} pts'),
                  trailing: editable
                      ? IconButton(
                          tooltip: 'Cambiar por otra',
                          icon: const Icon(Icons.swap_horiz_rounded),
                          onPressed: () => _replace(asInt(q['position'])),
                        )
                      : null,
                ),
              ),
          ]);
        },
      ),
    ]);
  }
}

class _QuestionPicker extends StatefulWidget {
  final Api api;
  const _QuestionPicker({required this.api});
  @override
  State<_QuestionPicker> createState() => _QuestionPickerState();
}

class _QuestionPickerState extends State<_QuestionPicker> {
  final _s = TextEditingController();
  late Future<List<Map<String, dynamic>>> _f = widget.api.adminQuestions();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Elegir pregunta'),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: Column(children: [
          TextField(
            controller: _s,
            decoration: const InputDecoration(hintText: 'Buscar', isDense: true),
            onSubmitted: (v) => setState(() => _f = widget.api.adminQuestions(search: v.trim())),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _f,
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                return ListView(children: [
                  for (final q in snap.data!.where((q) => q['active'] == true))
                    ListTile(
                      dense: true,
                      title: Text(_txt(q['prompt']), maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text('#${q['id']} · ${q['format']}'),
                      onTap: () => Navigator.pop(context, asInt(q['id'])),
                    ),
                ]);
              },
            ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))],
    );
  }
}
