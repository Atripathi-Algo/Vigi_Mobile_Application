import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app/brand.dart';
import '../app/common.dart';
import '../app/env.dart';
import '../app/fmt.dart';
import '../app/providers.dart';
import '../data/store.dart';
import '../services/google_accounts.dart';
import '../services/health.dart';
import '../services/local_brain.dart';
import '../services/notifications.dart';
import '../services/sfx.dart';
import '../services/steps.dart';
import '../vigil/vigil.dart';
import 'drive_sheet.dart';

/// Plays a sound for the previews, and says so when it cannot.
Future<void> _preview(BuildContext context, String asset, {double volume = 1}) async {
  final String? err = await SfxService.preview(asset, volume: volume);
  if (err != null && context.mounted) showVigilSnack(context, err);
}

/// 20 · Loadout · Settings
class LoadoutScreen extends ConsumerWidget {
  const LoadoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vigil;
    final t = context.vtype;
    final VigilStore s = ref.watch(storeProvider);
    final GoogleAccounts accounts = ref.watch(googleAccountsProvider);
    final LocalBrain brain = ref.watch(brainProvider);

    String sample() {
      final String base = switch (s.persona) {
        Persona.tactical => 'Hydration 1.2 of 3.0 L. Review at 19:00. Recommend 500 ml now.',
        Persona.butler => 'You\'re at 1.2 of 3 litres, and the review is at seven. Perhaps some water first?',
        Persona.quiet => '1.2 / 3.0 L · drink 500 ml',
      };
      return s.verbosity == Verbosity.detailed ? '$base Next check at 20:00.' : base;
    }

    Widget head(String text) => Padding(padding: const EdgeInsets.only(top: 18, bottom: 8), child: Text(text.toUpperCase(), style: t.label.copyWith(color: c.textFaint)));

    Widget toggleRow(String key, String title, String sub) => SizedBox(
          height: 60,
          child: Padding(
            padding: const EdgeInsets.only(left: 14, right: 8),
            child: Row(children: <Widget>[
              Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text(title, style: t.rowTitle), Text(sub.toUpperCase(), style: t.micro.copyWith(color: c.textFaint), maxLines: 1, overflow: TextOverflow.ellipsis)])),
              VigilSwitch(value: s.toggles[key] ?? false, onChanged: (bool v) => s.setToggle(key, v), semanticLabel: title),
            ]),
          ),
        );

    Widget linkRow(String title, String sub, String status, {VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 60,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: <Widget>[
                Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text(title, style: t.rowTitle), Text(sub.toUpperCase(), style: t.micro.copyWith(color: c.textFaint), maxLines: 1, overflow: TextOverflow.ellipsis)])),
                StatusChip(status, on: status == 'LINKED' || status == 'ON' || status == 'OK'),
              ]),
            ),
          ),
        );

    return VigilScaffold(
      title: 'Loadout',
      leading: VigilIconButton(icon: VigilIcons.chevronLeft, semanticLabel: 'Back', onPressed: () => context.pop()),
      body: ListView(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 28), children: <Widget>[
        VigilCard(
          child: Row(children: <Widget>[
            Container(width: 48, height: 48, decoration: BoxDecoration(border: Border.all(color: c.lineStrong), color: c.surfaceHigh), child: const Center(child: VigilEmblem(size: 28, semanticLabel: ''))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text(s.fullName.isEmpty ? s.nickname : s.fullName, style: t.title), Text('${s.nickname.isEmpty ? 'NO NICKNAME' : s.nickname.toUpperCase()} · 24H CLOCK · ₹ INR', style: t.micro.copyWith(color: c.textFaint))])),
          ]),
        ),
        head('$kAssistantName · Brain'),
        RowList(children: <Widget>[
          linkRow(
            'On-device model',
            switch (brain.status) {
              BrainStatus.notInstalled => 'MiniCPM5-1B · tap to download',
              BrainStatus.downloading => 'Downloading…',
              BrainStatus.ready => brain.enabled ? 'MiniCPM5-1B · answers on this phone' : 'Installed · switched off',
              BrainStatus.loading => 'Loading…',
              BrainStatus.busy => 'Thinking…',
            },
            brain.status == BrainStatus.notInstalled ? 'GET' : (brain.usable ? 'ON' : 'OFF'),
            onTap: () => context.push('/loadout/brain'),
          ),
        ]),
        head('$kAssistantName · Voice'),
        VigilCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Text('PERSONA', style: t.micro.copyWith(color: c.textFaint)),
            const SizedBox(height: 6),
            VigilSegmented<Persona>(segments: const <(Persona, String)>[(Persona.tactical, 'TACTICAL'), (Persona.butler, 'BUTLER'), (Persona.quiet, 'QUIET')], selected: s.persona, onSelected: s.setPersona),
            const SizedBox(height: 10),
            Text(sample(), style: t.caption.copyWith(color: c.textMuted)),
            const SizedBox(height: 14),
            Text('VERBOSITY', style: t.micro.copyWith(color: c.textFaint)),
            const SizedBox(height: 6),
            VigilSegmented<Verbosity>(segments: const <(Verbosity, String)>[(Verbosity.terse, 'TERSE'), (Verbosity.standard, 'STANDARD'), (Verbosity.detailed, 'DETAILED')], selected: s.verbosity, onSelected: s.setVerbosity),
          ]),
        ),
        head('API keys'),
        RowList(children: <Widget>[
          linkRow('API keys & services', 'Cloud AI · Calendar · Weather · Backend', 'EDIT', onTap: () => context.push('/loadout/keys')),
        ]),
        head('Notifications'),
        RowList(children: <Widget>[
          linkRow('Notifications', 'Reminders, wind-down, briefings', s.linkStatus['Notifications'] ?? 'ASK', onTap: () async {
            final bool ok = await NotificationService.requestPermission();
            s.setLink('Notifications', ok ? 'OK' : 'DENIED');
            if (!ok && context.mounted) showVigilSnack(context, 'Allow notifications for K in system settings');
          }),
          toggleRow('notifyOps', 'Ops reminders', 'Due in 30 min · next op in 15 min'),
          toggleRow('notifyProtocols', 'Protocol nudges', 'Streak at risk · 20:00'),
          linkRow('Send a test notification', 'Checks the critical channel', 'TEST', onTap: () async {
            await NotificationService.show('K // TEST', s.nickname.isEmpty ? 'Systems nominal.' : 'Systems nominal, ${s.nickname}.', channel: 'critical', payload: '/');
          }),
          linkRow('Exact reminder times', 'Alarms & reminders access', s.linkStatus['Exact alarms'] ?? 'ASK', onTap: () async {
            await NotificationService.requestExactAlarms();
            s.setLink('Exact alarms', await NotificationService.canScheduleExact() ? 'OK' : 'DENIED');
          }),
          linkRow('Background & battery', 'ColorOS: allow auto-start, no restrictions', 'OPEN', onTap: () => openAppSettings()),
        ]),
        head('Sounds'),
        RowList(children: <Widget>[
          toggleRow('sfx', 'Sound effects', 'In-app cues · original audio'),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              Text('EFFECT VOLUME', style: t.micro.copyWith(color: c.textFaint)),
              const SizedBox(height: 6),
              VigilSegmented<int>(
                segments: const <(int, String)>[(0, 'LOW'), (1, 'MEDIUM'), (2, 'HIGH')],
                selected: s.sfxLevel,
                onSelected: (int v) {
                  s.setSfxLevel(v);
                  SfxService.configure(on: s.toggles['sfx'] ?? true, level: v);
                  SfxService.play(Sfx.tick);
                },
              ),
              const SizedBox(height: 4),
              Text('PREVIEWS PLAY AT MEDIA VOLUME. REAL ALERTS FOLLOW THE NOTIFICATION VOLUME', style: t.micro.copyWith(color: c.textFaint, fontSize: 9)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text('PREVIEW EFFECTS', style: t.micro.copyWith(color: c.textFaint)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                for (final Sfx e in Sfx.values)
                  VigilButton(label: e.name, variant: VigilButtonVariant.secondary, onPressed: () => _preview(context, 'sfx_${e.name}', volume: SfxService.volume)),
              ]),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text('PREVIEW ALERT SOUNDS', style: t.micro.copyWith(color: c.textFaint)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                for (final (String, String) a in const <(String, String)>[('bat_critical', 'critical'), ('bat_ops', 'ops'), ('bat_sleep', 'sleep'), ('bat_brief', 'briefing'), ('bat_soft', 'soft')])
                  VigilButton(label: a.$2, variant: VigilButtonVariant.accent, onPressed: () => _preview(context, a.$1)),
              ]),
            ]),
          ),
        ]),
        head('Briefings'),
        RowList(children: <Widget>[
          toggleRow('spoken', 'Spoken replies', 'Reads typed replies aloud'),
          toggleRow('dawn', 'Dawn briefing', Fmt.hm(s.wakeMin)),
          toggleRow('debrief', 'Night debrief', Fmt.hm(s.bedMin - 30)),
          linkRow('Open dawn briefing', 'Preview now', 'OPEN', onTap: () => context.push('/briefing')),
          linkRow('Open night debrief', 'Preview now', 'OPEN', onTap: () => context.push('/debrief')),
        ]),
        head('Links'),
        RowList(children: <Widget>[
          linkRow('Step sensor', 'Phone step counter', s.linkStatus['Step sensor'] ?? 'ASK', onTap: () async {
            final bool ok = await StepService.start(s, request: true);
            s.setLink('Step sensor', ok ? 'OK' : 'DENIED');
            if (!ok && context.mounted) showVigilSnack(context, 'Allow Physical activity for K in system settings');
          }),
          linkRow(
            'Google accounts',
            accounts.hasAny ? accounts.accounts.map((GoogleAccount a) => '${a.label} ${a.email}').join(' · ') : 'Link up to two · calendar',
            accounts.hasAny || Env.hasCalendar ? 'LINKED' : 'ASK',
            onTap: () => context.push('/loadout/accounts'),
          ),
          ValueListenableBuilder<String>(
            valueListenable: HealthService.status,
            builder: (BuildContext ctx, String st, Widget? _) => linkRow(
              'Health Connect',
              s.healthSyncedAt == null ? 'Sleep, weight, resting heart rate' : 'Synced ${Fmt.time(s.healthSyncedAt!)} · tap to sync',
              s.linkStatus['Health Connect'] == 'OK' ? (st == 'OFF' ? 'OK' : st) : (s.linkStatus['Health Connect'] ?? 'ASK'),
              onTap: () async {
                final bool ok = s.linkStatus['Health Connect'] == 'OK' ? await HealthService.sync(s, force: true) : await HealthService.connect(s);
                if (context.mounted) showVigilSnack(context, 'Health Connect · ${HealthService.status.value}${ok ? '' : '. Install or allow it, or log by hand'}');
              },
            ),
          ),
          linkRow('Usage access', 'Bridge not built', 'ASK', onTap: () => showVigilSnack(context, 'Usage-stats bridge is not built')),
          linkRow('Bank SMS parser', 'Sideload build only', 'OFF'),
        ]),
        head('Home screen'),
        VigilCard(
          child: Text('Long-press the home screen, open Widgets, and add K · Objectives (4×2) or K · Readiness (2×2). Tap an objective to check it off, or +250 ML to log water, without opening the app.', style: t.caption.copyWith(color: c.textMuted)),
        ),
        head('Data & privacy'),
        RowList(children: <Widget>[
          toggleRow('vaultLock', 'Vault lock', 'Locks when you leave the tab'),
          SizedBox(
            height: 60,
            child: Padding(
              padding: const EdgeInsets.only(left: 14, right: 8),
              child: Row(children: <Widget>[
                Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text('Cloud AI for hard requests', style: t.rowTitle), Text(Env.hasCloudAi ? 'SENDS SITREP + QUESTION · ${Env.cloudAiProvider.toUpperCase()}' : 'ADD CLOUD_AI_API_KEY TO .ENV', style: t.micro.copyWith(color: c.textFaint), maxLines: 1, overflow: TextOverflow.ellipsis)])),
                VigilSwitch(
                  value: s.toggles['cloudAi'] ?? false,
                  semanticLabel: 'Cloud AI for hard requests',
                  onChanged: (bool v) {
                    if (v && !Env.hasCloudAi) {
                      showVigilSnack(context, 'Add a Cloud AI key under API keys first');
                      return;
                    }
                    if (v && Env.cloudAiProvider == 'gemini') {
                      showVigilSnack(context, 'Gemini free tier: Google may use what you send to improve its products');
                    }
                    s.setToggle('cloudAi', v);
                  },
                ),
              ]),
            ),
          ),
          linkRow(
            'Google Drive backup',
            accounts.hasAny ? 'Private app folder · back up or restore' : 'Link a Google account first',
            accounts.hasAny ? 'OPEN' : 'ASK',
            onTap: () => accounts.hasAny ? showDriveSheet(context, s) : context.push('/loadout/accounts'),
          ),
          linkRow('Export data', 'Copy JSON snapshot', 'OPEN', onTap: () async {
            await Clipboard.setData(ClipboardData(text: s.sitrep(DateTime.now())));
            if (context.mounted) showVigilSnack(context, 'Snapshot copied');
          }),
          linkRow('Assistant log', '${s.chat.length} messages this session', 'OPEN', onTap: () => context.go('/vigil')),
          InkWell(
            onTap: () => _erase(context, s),
            child: SizedBox(height: 56, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Align(alignment: Alignment.centerLeft, child: Text('ERASE ALL', style: t.button.copyWith(color: c.critical))))),
          ),
        ]),
        const SizedBox(height: 22),
        head('Setup'),
        RowList(children: <Widget>[
          linkRow('Run $kAssistantName setup again', 'Name, Google, $kAssistantName\'s brain, permissions, voice', 'OPEN', onTap: () => context.push('/boot')),
        ]),
        Center(child: Text('K v1.0 · BUILD 0002', style: t.micro.copyWith(color: c.textFaint))),
      ]),
    );
  }

  void _erase(BuildContext context, VigilStore s) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('ERASE ALL'),
        content: const Text('Erase all K data on this phone? This can\'t be undone.'),
        actions: <Widget>[
          VigilButton(label: 'Cancel', variant: VigilButtonVariant.secondary, onPressed: () => Navigator.pop(ctx)),
          VigilButton(
            label: 'Erase all',
            variant: VigilButtonVariant.critical,
            onPressed: () async {
              Navigator.pop(ctx);
              await s.eraseAll();
              if (context.mounted) context.go('/boot');
            },
          ),
        ],
      ),
    );
  }
}
