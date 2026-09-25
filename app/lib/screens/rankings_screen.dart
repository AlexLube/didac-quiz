import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/ads.dart';
import '../share_text.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/common.dart';

class RankingsScreen extends StatefulWidget {
  const RankingsScreen({super.key});

  @override
  State<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends State<RankingsScreen> {
  String _scope = 'world';
  String _period = 'day';
  Leaderboard? _board;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = AppState.instance;
    if (_scope != 'world' && state.profile == null) {
      setState(() {
        _board = null;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final b = await state.api.leaderboard(_scope, _period);
      if (mounted) setState(() => _board = b);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _labelTitle() {
    final l = _board?.label ?? {};
    switch (l['type']) {
      case 'country':
        return Strings.pick(l['name']);
      case 'city':
        return '${l['name']}';
      case 'region':
        return tr('area_of', {'name': '${l['name']}'});
      default:
        return tr('world');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'world', label: Text(tr('world')), icon: const Icon(Icons.public_rounded)),
              ButtonSegment(value: 'country', label: Text(tr('country')), icon: const Icon(Icons.flag_rounded)),
              ButtonSegment(value: 'city', label: Text(tr('local')), icon: const Icon(Icons.location_on_rounded)),
            ],
            selected: {_scope},
            onSelectionChanged: (s) {
              setState(() => _scope = s.first);
              _load();
            },
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final p in const ['day', 'week', 'month', 'all'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(tr(p == 'all' ? 'all_time' : p)),
                    selected: _period == p,
                    onSelected: (_) {
                      setState(() => _period = p);
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _content()),
        const BannerSlot(),
      ],
    );
  }

  Widget _content() {
    if (_scope != 'world' && AppState.instance.profile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(tr('rankings_need_account'), textAlign: TextAlign.center),
        ),
      );
    }
    if (_error != null) return ErrorView(message: tr('error_generic'), onRetry: _load);
    final b = _board;
    if (b == null || (_loading && b.top.isEmpty)) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_labelTitle(),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              Text('${b.totalPlayers} ${tr('players')}',
                  style: const TextStyle(color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 10),
          if (b.me != null) ...[
            _RowTile(b.me!, highlight: true),
            const SizedBox(height: 10),
          ],
          if (b.top.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(tr('no_players_yet'), textAlign: TextAlign.center),
            ),
          for (final r in b.top) _RowTile(r),
          if (b.around.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Center(child: Icon(Icons.more_vert_rounded, color: AppColors.textMuted)),
            ),
            for (final r in b.around) _RowTile(r),
          ],
        ],
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  final LeaderboardRow row;
  final bool highlight;
  const _RowTile(this.row, {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final medal = switch (row.rank) {
      1 => const Color(0xFFFFD700),
      2 => const Color(0xFFC0C0C0),
      3 => const Color(0xFFCD7F32),
      _ => AppColors.surfaceHigh,
    };
    final subtitle = [
      if (row.city != null) row.city!,
      row.countryCode,
      formatDuration(row.ms),
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: row.isMe ? AppColors.amber.withValues(alpha: 0.15) : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: highlight || row.isMe ? Border.all(color: AppColors.amber, width: 1.5) : null,
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: medal,
          foregroundColor: row.rank <= 3 ? Colors.black : AppColors.text,
          child: Text('${row.rank}', style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
        title: Text(row.isMe ? '${row.alias} (${tr('you')})' : row.alias,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textMuted)),
        trailing: Text('${row.points}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.amber)),
      ),
    );
  }
}
