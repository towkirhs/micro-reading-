import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store});

  final AppStore store;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Settings _s = widget.store.settings;

  String _fmt(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  Future<void> _pick({required bool start}) async {
    final current = start ? _s.awakeStartMin : _s.awakeEndMin;
    final messenger = ScaffoldMessenger.of(context);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null || !mounted) return;
    final minutes = picked.hour * 60 + picked.minute;
    final next = start
        ? _s.copyWith(awakeStartMin: minutes)
        : _s.copyWith(awakeEndMin: minutes);
    if (next.awakeEndMin - next.awakeStartMin < 60) {
      messenger.showSnackBar(const SnackBar(
        content: Text('The awake window must be at least an hour long, '
            'and end after it starts.'),
      ));
      return;
    }
    setState(() => _s = next);
    await widget.store.updateSettings(next);
  }

  Widget _slider({
    required String title,
    required int value,
    required int min,
    required int max,
    required Settings Function(int) apply,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('$title: $value'),
        ),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          label: '$value',
          onChanged: (v) => setState(() => _s = apply(v.round())),
          onChangeEnd: (_) => widget.store.updateSettings(_s),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.wb_sunny_outlined),
            title: const Text('Awake from'),
            trailing: Text(_fmt(_s.awakeStartMin)),
            onTap: () => _pick(start: true),
          ),
          ListTile(
            leading: const Icon(Icons.nightlight_outlined),
            title: const Text('Awake until'),
            trailing: Text(_fmt(_s.awakeEndMin)),
            onTap: () => _pick(start: false),
          ),
          _slider(
            title: 'Daily cap (most pieces per day)',
            value: _s.dailyCap,
            min: 1,
            max: 20,
            apply: (v) => _s.copyWith(dailyCap: v),
          ),
          _slider(
            title: 'Pieces per day when a book has no goal',
            value: _s.defaultPerDay,
            min: 1,
            max: 20,
            apply: (v) => _s.copyWith(defaultPerDay: v),
          ),
          _slider(
            title: 'Minimum gap between notifications (minutes)',
            value: _s.minGapMin,
            min: 10,
            max: 180,
            apply: (v) => _s.copyWith(minGapMin: v),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Send a test notification'),
            subtitle: const Text('Arrives in about 15 seconds'),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              await widget.store.sendTestNotification();
              messenger.showSnackBar(const SnackBar(
                content: Text('Lock your phone and wait a few seconds.'),
              ));
            },
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'If notifications arrive late or not at all, open Android '
              'Settings → Apps → Micro Reader → Battery and choose '
              '"Unrestricted". Open the app every few days: it plans '
              'notifications three days ahead.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
