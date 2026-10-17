import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../theme.dart';

/// Fragmento de un tráiler oficial de YouTube (preguntas de formato «video»).
class TrailerClip extends StatefulWidget {
  final String videoId;
  final int startS;
  final int endS;
  final bool stop;
  const TrailerClip({super.key, required this.videoId, this.startS = 0, this.endS = 0, this.stop = false});

  @override
  State<TrailerClip> createState() => _TrailerClipState();
}

class _TrailerClipState extends State<TrailerClip> {
  late final YoutubePlayerController _c = YoutubePlayerController.fromVideoId(
    videoId: widget.videoId,
    autoPlay: true,
    startSeconds: widget.startS.toDouble(),
    endSeconds: widget.endS > widget.startS ? widget.endS.toDouble() : null,
    params: const YoutubePlayerParams(
      showControls: true,
      showFullscreenButton: false,
      enableCaption: false,
      showVideoAnnotations: false,
      strictRelatedVideos: true,
      playsInline: true,
    ),
  );

  @override
  void didUpdateWidget(TrailerClip old) {
    super.didUpdateWidget(old);
    if (widget.stop && !old.stop) _c.pauseVideo();
  }

  @override
  void dispose() {
    _c.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.18), blurRadius: 24)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: YoutubePlayer(controller: _c, aspectRatio: 16 / 9, backgroundColor: Colors.black),
      ),
    );
  }
}
