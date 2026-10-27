import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/store.dart';
import '../screens/accounts_screen.dart';
import '../screens/api_keys_screen.dart';
import '../screens/setup_screen.dart';
import '../screens/brain_screen.dart';
import '../screens/briefing_screen.dart';
import '../screens/command_screen.dart';
import '../screens/debrief_screen.dart';
import '../screens/deep_ops_screen.dart';
import '../screens/loadout_screen.dart';
import '../screens/ops_screen.dart';
import '../screens/protocols_screen.dart';
import '../screens/sleep_screens.dart';
import '../screens/uplink_screen.dart';
import '../screens/vault_screen.dart';
import 'shell.dart';

final GlobalKey<NavigatorState> rootNavKey = GlobalKey<NavigatorState>(debugLabel: 'root');

Page<void> _noAnim(Widget child, GoRouterState s) => NoTransitionPage<void>(key: s.pageKey, child: child);

GoRouter buildRouter(VigilStore store) {
  return GoRouter(
    navigatorKey: rootNavKey,
    initialLocation: store.booted ? '/' : '/boot',
    routes: <RouteBase>[
      GoRoute(path: '/boot', builder: (BuildContext c, GoRouterState s) => const SetupScreen()),
      GoRoute(path: '/briefing', builder: (BuildContext c, GoRouterState s) => const BriefingScreen()),
      GoRoute(path: '/debrief', builder: (BuildContext c, GoRouterState s) => const DebriefScreen()),
      GoRoute(
        path: '/loadout',
        builder: (BuildContext c, GoRouterState s) => const LoadoutScreen(),
        routes: <RouteBase>[
          GoRoute(path: 'keys', builder: (BuildContext c, GoRouterState s) => const ApiKeysScreen()),
          GoRoute(path: 'accounts', builder: (BuildContext c, GoRouterState s) => const AccountsScreen()),
          GoRoute(path: 'brain', builder: (BuildContext c, GoRouterState s) => const BrainScreen()),
        ],
      ),
      GoRoute(
        path: '/deep-ops',
        builder: (BuildContext c, GoRouterState s) => DeepOpsScreen(objectiveId: s.uri.queryParameters['objective'], workout: s.uri.queryParameters['mode'] == 'workout'),
      ),
      GoRoute(
        path: '/protocols/vitals/sleep',
        builder: (BuildContext c, GoRouterState s) => const SleepScreen(schedule: false),
        routes: <RouteBase>[
          GoRoute(path: 'schedule', builder: (BuildContext c, GoRouterState s) => const SleepScreen(schedule: true)),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (BuildContext c, GoRouterState s, StatefulNavigationShell shell) => AppShell(shell: shell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(path: '/', builder: (BuildContext c, GoRouterState s) => const CommandScreen()),
          ]),
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(path: '/ops/objectives', pageBuilder: (BuildContext c, GoRouterState s) => _noAnim(const OpsScreen(timeline: false), s)),
            GoRoute(path: '/ops/timeline', pageBuilder: (BuildContext c, GoRouterState s) => _noAnim(const OpsScreen(timeline: true), s)),
          ]),
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(path: '/vigil', builder: (BuildContext c, GoRouterState s) => const UplinkScreen()),
          ]),
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(path: '/protocols/habits', pageBuilder: (BuildContext c, GoRouterState s) => _noAnim(const ProtocolsScreen(view: ProtocolsView.habits), s)),
            GoRoute(path: '/protocols/vitals', pageBuilder: (BuildContext c, GoRouterState s) => _noAnim(const ProtocolsScreen(view: ProtocolsView.vitals), s)),
            GoRoute(path: '/protocols/screen', pageBuilder: (BuildContext c, GoRouterState s) => _noAnim(const ProtocolsScreen(view: ProtocolsView.screen), s)),
          ]),
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(path: '/vault/ledger', pageBuilder: (BuildContext c, GoRouterState s) => _noAnim(const VaultScreen(log: false), s)),
            GoRoute(path: '/vault/log', pageBuilder: (BuildContext c, GoRouterState s) => _noAnim(const VaultScreen(log: true), s)),
          ]),
        ],
      ),
    ],
  );
}
