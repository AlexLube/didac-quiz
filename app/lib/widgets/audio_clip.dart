import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../strings.dart';
import '../theme.dart';

/// Fragmento de audio de la pregunta: suena solo al aparecer y se puede repetir.
class AudioClip extends StatefulWidget {
  final String url;
  final int startMs;
  final String? attribution;
  final bool stop; // se detiene al responder

  const AudioClip({
    super.key,
    required this.url,
    this.startMs = 0,
    this.attribution,
    this.stop = false,
  });

  @override
  State<AudioClip> createState() => _AudioClipState();
}

class _AudioClipState extends State<AudioClip> with SingleTickerProviderStateMixin {
  final _player = AudioPlayer();
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  bool _playing = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      final playing = s == PlayerState.playing;
      setState(() => _playing = playing);
      if (playing) {
        _pulse.repeat(reverse: true);
      } else {
        _pulse.stop();
      }
    });
    _play();
  }

  Future<void> _play() async {
    try {
      await _player.stop();
      await _player.play(UrlSource(widget.url), position: Duration(milliseconds: widget.startMs));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(covariant AudioClip old) {
    super.didUpdateWidget(old);
    if (widget.stop && !old.stop) _player.stop();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                ScaleTransition(
                  scale: Tween(begin: 1.0, end: 1.15).animate(_pulse),
                  child: const Icon(Icons.music_note_rounded, size: 44, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _failed ? tr('audio_error') : tr('listen'),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: Colors.black),
                  onPressed: widget.stop ? null : (_playing ? () => _player.pause() : _play),
                  icon: Icon(_playing ? Icons.pause_rounded : Icons.replay_rounded,
                      color: Colors.white),
                ),
              ],
            ),
          ),
          if (widget.attribution != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(widget.attribution!,
                  style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
            ),
        ],
      ),
    );
  }
}
