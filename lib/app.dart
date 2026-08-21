import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/history/history_screen.dart';
import 'features/onboarding/welcome_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/snap/snap_screen.dart';
import 'providers.dart';

class NoiseAlertApp extends StatelessWidget {
  const NoiseAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flightpath Watch Report',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B4965)),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B4965),
          brightness: Brightness.dark,
        ),
      ),
      home: const _Root(),
    );
  }
}

/// The welcome form, or the app.
///
/// A ConsumerWidget rather than a route pushed over the top, because
/// [SnapScreen] opens the microphone in its `initState`. Anything that leaves
/// it built underneath a welcome screen asks for permission before the user
/// has been told what the app is, which is how a Deny happens.
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(onboardedProvider) ? const HomeShell() : const WelcomeScreen();
}

/// Which tab is showing.
///
/// Lifted out of [_HomeShellState] because the record screen needs it. The
/// screen starts recording the moment the app opens, and an [IndexedStack]
/// keeps it alive and none the wiser when the user walks off to Settings --
/// so without this it would carry on recording a conversation nobody asked it
/// to record, and hand back a snap on the way out.
final StateProvider<int> homeTabProvider = StateProvider<int>((Ref ref) => 0);

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const List<Widget> _pages = <Widget>[
    SnapScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final int index = ref.watch(homeTabProvider);
    return Scaffold(
      body: IndexedStack(index: index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (int i) =>
            ref.read(homeTabProvider.notifier).state = i,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.mic_none),
            selectedIcon: Icon(Icons.mic),
            label: 'Record',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
