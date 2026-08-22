import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

/// Play the saved clip before deciding whether to send it.
///
/// Attaching a recording of your own street to an email is not a decision to
/// make blind: it may have caught a neighbour's conversation as readily as the
/// aeroplane. So the toggle sits next to the play button, not in Settings.
class ClipPlayer extends StatefulWidget {
  const ClipPlayer({
    super.key,
    required this.path,
    required this.attach,
    required this.onAttachChanged,
  });

  final String path;
  final bool attach;
  final ValueChanged<bool> onAttachChanged;

  @override
  State<ClipPlayer> createState() => _ClipPlayerState();
}

class _ClipPlayerState extends State<ClipPlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool _loadFailed = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final Duration? duration = await _player.setFilePath(widget.path);
      if (!mounted) return;
      setState(() => _duration = duration ?? Duration.zero);

      _positionSub = _player.positionStream.listen((Duration p) {
        if (mounted) setState(() => _position = p);
      });
      _stateSub = _player.playerStateStream.listen((PlayerState s) async {
        if (s.processingState == ProcessingState.completed) {
          await _player.pause();
          await _player.seek(Duration.zero);
        }
        if (mounted) setState(() {});
      });
    } on Object {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  @override
  void dispose() {
    unawaited(_positionSub?.cancel());
    unawaited(_stateSub?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (_loadFailed || !File(widget.path).existsSync()) {
      return ListTile(
        leading: const Icon(Icons.error_outline),
        title: const Text('Clip unavailable'),
        subtitle: Text(
          'The recording could not be opened. The measurement is unaffected.',
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    final bool playing = _player.playing;
    final double progress = _duration.inMilliseconds == 0
        ? 0
        : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            IconButton.filledTonal(
              onPressed: () async {
                if (playing) {
                  await _player.pause();
                } else {
                  await _player
                      .seek(_position >= _duration ? Duration.zero : _position);
                  await _player.play();
                }
                if (mounted) setState(() {});
              },
              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              tooltip: playing ? 'Pause' : 'Play the clip',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child:
                        LinearProgressIndicator(value: progress, minHeight: 6),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_format(_position)} / ${_format(_duration)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: widget.attach,
          onChanged: widget.onAttachChanged,
          title: const Text('Attach this clip to the complaint'),
          subtitle: Text(
            widget.attach
                ? 'The recording will be attached to the email.'
                : 'Kept on this device only.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  static String _format(Duration d) {
    final String s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '${d.inMinutes}:$s';
  }
}
