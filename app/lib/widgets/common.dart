import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../strings.dart';
import '../theme.dart';

class DifficultyBadge extends StatelessWidget {
  final int difficulty;
  const DifficultyBadge(this.difficulty, {super.key});

  @override
  Widget build(BuildContext context) {
    final label = [tr('easy'), tr('medium'), tr('hard')][difficulty.clamp(1, 3) - 1];
    final color = AppColors.forDifficulty(difficulty);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        '$label · $difficulty ${difficulty == 1 ? tr('pt') : tr('pts')}',
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
      ),
    );
  }
}

/// Barra de tiempo que se vacía. El tiempo real lo cuenta el servidor;
/// esta barra es solo visual.
class TimerBar extends StatelessWidget {
  final double fraction; // 1 = lleno, 0 = agotado
  const TimerBar(this.fraction, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = fraction > 0.5
        ? AppColors.success
        : (fraction > 0.25 ? AppColors.amber : AppColors.error);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LinearProgressIndicator(
        value: fraction.clamp(0, 1),
        minHeight: 10,
        backgroundColor: AppColors.surfaceHigh,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

enum OptionState { idle, selected, correct, wrong, disabled, removed }

class OptionButton extends StatelessWidget {
  final String label;
  final String letter;
  final OptionState state;
  final VoidCallback? onTap;

  const OptionButton({
    super.key,
    required this.label,
    required this.letter,
    required this.state,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color border = AppColors.surfaceHigh;
    Color fill = AppColors.surface;
    switch (state) {
      case OptionState.selected:
        border = AppColors.amber;
      case OptionState.correct:
        border = AppColors.success;
        fill = AppColors.success.withValues(alpha: 0.2);
      case OptionState.wrong:
        border = AppColors.error;
        fill = AppColors.error.withValues(alpha: 0.2);
      default:
        break;
    }
    final removed = state == OptionState.removed;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: removed ? 0.25 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border, width: 2),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: state == OptionState.idle ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(letter, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        decoration: removed ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: Text(tr('retry'))),
          ],
        ),
      ),
    );
  }
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Selector de país (lista cerrada) y ciudad (búsqueda en el servidor).
class LocationPicker extends StatefulWidget {
  final void Function(String country, City? city) onChanged;
  const LocationPicker({super.key, required this.onChanged});

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  List<Country> _countries = [];
  String? _country;
  City? _city;
  List<City> _results = [];
  final _query = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadCountries();
  }

  Future<void> _loadCountries() async {
    try {
      final list = await AppState.instance.api.countries();
      list.sort((a, b) => _name(a).compareTo(_name(b)));
      if (!mounted) return;
      setState(() {
        _countries = list;
        _country = list.any((c) => c.code == 'ES') && Strings.lang == 'es' ? 'ES' : null;
      });
      if (_country != null) _search('');
    } catch (_) {}
  }

  String _name(Country c) => Strings.lang == 'es' ? c.nameEs : c.nameEn;

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (_country == null) return;
      try {
        final r = await AppState.instance.api.searchCities(_country!, q.trim());
        if (mounted) setState(() => _results = r);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('country-${_countries.length}'),
          initialValue: _country,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('choose_country')),
          items: [
            for (final c in _countries)
              DropdownMenuItem(value: c.code, child: Text(_name(c), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            setState(() {
              _country = v;
              _city = null;
              _results = [];
              _query.clear();
            });
            if (v != null) {
              widget.onChanged(v, null);
              _search('');
            }
          },
        ),
        const SizedBox(height: 12),
        if (_city != null)
          ListTile(
            tileColor: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: const Icon(Icons.location_city_rounded, color: AppColors.amber),
            title: Text(_city!.name),
            trailing: const Icon(Icons.edit_rounded),
            onTap: () => setState(() => _city = null),
          )
        else ...[
          TextField(
            controller: _query,
            enabled: _country != null,
            decoration: InputDecoration(
              labelText: tr('search_city'),
              prefixIcon: const Icon(Icons.search_rounded),
            ),
            onChanged: _search,
          ),
          const SizedBox(height: 6),
          for (final c in _results.take(6))
            ListTile(
              dense: true,
              title: Text(c.name),
              onTap: () {
                setState(() => _city = c);
                widget.onChanged(_country!, c);
              },
            ),
        ],
      ],
    );
  }
}
