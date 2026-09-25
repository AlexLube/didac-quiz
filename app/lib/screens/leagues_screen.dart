import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/api.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'rankings_screen.dart';

/// Lista de mis ligas privadas, con botones para crear o unirse.
class LeaguesPanel extends StatefulWidget {
  const LeaguesPanel({super.key});

  @override
  State<LeaguesPanel> createState() => _LeaguesPanelState();
}

class _LeaguesPanelState extends State<LeaguesPanel> {
  List<League>? _leagues;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final l = await AppState.instance.api.myLeagues();
      if (mounted) setState(() => _leagues = l);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<String?> _askText({required String title, required String label, bool code = false}) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: code ? 6 : 40,
          textCapitalization: code ? TextCapitalization.characters : TextCapitalization.sentences,
          inputFormatters:
              code ? [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]'))] : null,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(tr('save'))),
        ],
      ),
    );
  }

  Future<void> _create() async {
    final name = await _askText(title: tr('create_league'), label: tr('league_name'));
    if (name == null || name.isEmpty) return;
    try {
      final league = await AppState.instance.api.createLeague(name);
      await _load();
      if (mounted) _open(league, showInvite: true);
    } on ApiError catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  Future<void> _join() async {
    final code = await _askText(title: tr('join_league'), label: tr('invite_code'), code: true);
    if (code == null || code.isEmpty) return;
    try {
      final league = await AppState.instance.api.joinLeague(code);
      await _load();
      if (!mounted) return;
      showSnack(context, tr('joined_league', {'name': league.name}));
      _open(league);
    } on ApiError catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  Future<void> _open(League league, {bool showInvite = false}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LeagueScreen(league: league, showInviteOnOpen: showInvite),
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (AppState.instance.profile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(tr('leagues_need_account'), textAlign: TextAlign.center),
        ),
      );
    }
    if (_error != null) return ErrorView(message: tr('error_generic'), onRetry: _load);
    final leagues = _leagues;
    if (leagues == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          Text(tr('leagues_intro'), style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(tr('create_league')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _join,
                  icon: const Icon(Icons.vpn_key_rounded),
                  label: Text(tr('join_league')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (leagues.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(tr('no_leagues'), textAlign: TextAlign.center),
            ),
          for (final l in leagues)
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.surfaceHigh,
                  child: Icon(Icons.groups_rounded, color: AppColors.amber),
                ),
                title: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(tr('members_n', {'n': l.members}) +
                    (l.isOwner ? ' · ${tr('owner')}' : '')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _open(l),
              ),
            ),
        ],
      ),
    );
  }
}

/// Clasificación de una liga, con invitación y opciones.
class LeagueScreen extends StatefulWidget {
  final League league;
  final bool showInviteOnOpen;
  const LeagueScreen({super.key, required this.league, this.showInviteOnOpen = false});

  @override
  State<LeagueScreen> createState() => _LeagueScreenState();
}

class _LeagueScreenState extends State<LeagueScreen> {
  String _period = 'week';
  Leaderboard? _board;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.showInviteOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _invite());
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final b = await AppState.instance.api.leagueLeaderboard(widget.league.id, _period);
      if (mounted) setState(() => _board = b);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _invite() async {
    final l = widget.league;
    await SharePlus.instance.share(
      ShareParams(text: tr('invite_text', {'name': l.name, 'code': l.inviteCode})),
    );
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: body.isEmpty ? null : Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(title)),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _run(Future<void> Function() action, {bool close = false}) async {
    try {
      await action();
      if (!mounted) return;
      if (close) {
        Navigator.of(context).pop();
      } else {
        _load();
      }
    } on ApiError catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  Future<void> _menu(String value) async {
    final api = AppState.instance.api;
    final id = widget.league.id;
    if (value == 'leave' && await _confirm(tr('leave_league'), '')) {
      await _run(() => api.leaveLeague(id), close: true);
    } else if (value == 'delete' && await _confirm(tr('delete_league'), tr('delete_league_confirm'))) {
      await _run(() => api.deleteLeague(id), close: true);
    }
  }

  Future<void> _removeMember(LeaderboardRow row) async {
    if (!widget.league.isOwner || row.isMe) return;
    final label = tr('remove_member', {'alias': row.alias});
    if (await _confirm(label, '')) {
      await _run(() => AppState.instance.api.removeLeagueMember(widget.league.id, row.alias));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.league;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => [
              PopupMenuItem(value: 'leave', child: Text(tr('leave_league'))),
              if (l.isOwner) PopupMenuItem(value: 'delete', child: Text(tr('delete_league'))),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: _invite,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: AppColors.heroGradient,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('invite_code'), style: const TextStyle(color: Colors.white70)),
                            Text(l.inviteCode,
                                style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 4,
                                    color: Colors.white)),
                          ],
                        ),
                      ),
                      const Icon(Icons.ios_share_rounded, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(tr('invite_friends'),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
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
            Expanded(child: _table()),
          ],
        ),
      ),
    );
  }

  Widget _table() {
    if (_error != null) return ErrorView(message: tr('error_generic'), onRetry: _load);
    final b = _board;
    if (b == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          for (final r in b.top)
            GestureDetector(
              onLongPress: () => _removeMember(r),
              child: RankingRow(r),
            ),
        ],
      ),
    );
  }
}
