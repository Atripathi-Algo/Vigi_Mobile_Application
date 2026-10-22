import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/assistant.dart';
import '../data/store.dart';
import '../services/google_accounts.dart';
import '../services/output_sync.dart';

/// The linked Google accounts (up to two).
final ChangeNotifierProvider<GoogleAccounts> googleAccountsProvider = ChangeNotifierProvider<GoogleAccounts>((Ref ref) => GoogleAccounts.instance);

/// Overridden in main() with the loaded store.
final ChangeNotifierProvider<VigilStore> storeProvider =
    ChangeNotifierProvider<VigilStore>((Ref ref) => throw UnimplementedError('storeProvider must be overridden'));

final Provider<Assistant> assistantProvider = Provider<Assistant>((Ref ref) => Assistant(ref.read(storeProvider)));

/// Wall clock, ticking every 30 s so greetings and T-minus counters stay fresh.
final StreamProvider<DateTime> clockProvider = StreamProvider<DateTime>((Ref ref) async* {
  yield DateTime.now();
  yield* Stream<DateTime>.periodic(const Duration(seconds: 30), (_) => DateTime.now());
});

/// The running widget/reminder syncer, set once the app has started.
final StateProvider<OutputSync?> outputSyncProvider = StateProvider<OutputSync?>((Ref ref) => null);
