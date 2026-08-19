import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'core/device_info.dart';
import 'data/audio/recorder_service.dart';
import 'data/flights/adsb_source.dart';
import 'data/flights/flight_lookup_service.dart';
import 'data/flights/opensky_source.dart';
import 'data/flights/tar1090_source.dart';
import 'data/snap_service.dart';
import 'data/storage/database.dart';
import 'domain/profile.dart';
import 'domain/settings.dart';
import 'domain/snap.dart';

/// Overridden in `main()` once the database is open, so the rest of the app can
/// depend on it synchronously instead of unwrapping an AsyncValue everywhere.
final Provider<AppDatabase> databaseProvider = Provider<AppDatabase>(
  (Ref ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

/// Likewise: loaded before the first frame so Settings never flashes empty
/// fields over the user's saved details.
final Provider<AppSettings> initialSettingsProvider = Provider<AppSettings>(
  (Ref ref) =>
      throw UnimplementedError('initialSettingsProvider must be overridden'),
);

final Provider<ComplainantProfile> initialProfileProvider =
    Provider<ComplainantProfile>(
  (Ref ref) =>
      throw UnimplementedError('initialProfileProvider must be overridden'),
);

final Provider<http.Client> httpClientProvider =
    Provider<http.Client>((Ref ref) {
  final http.Client client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final Provider<DeviceInfoService> deviceInfoProvider =
    Provider<DeviceInfoService>((Ref ref) => DeviceInfoService());

// --- settings & profile ---------------------------------------------------

class SettingsController extends StateNotifier<AppSettings> {
  SettingsController(this._db, AppSettings initial) : super(initial);

  final AppDatabase _db;

  Future<void> update(AppSettings settings) async {
    state = settings;
    await _db.saveSettings(settings);
  }

  Future<void> edit(AppSettings Function(AppSettings) change) =>
      update(change(state));
}

final StateNotifierProvider<SettingsController, AppSettings> settingsProvider =
    StateNotifierProvider<SettingsController, AppSettings>(
  (Ref ref) => SettingsController(
    ref.watch(databaseProvider),
    ref.watch(initialSettingsProvider),
  ),
);

class ProfileController extends StateNotifier<ComplainantProfile> {
  ProfileController(this._db, ComplainantProfile initial) : super(initial);

  final AppDatabase _db;

  Future<void> update(ComplainantProfile profile) async {
    state = profile;
    await _db.saveProfile(profile);
  }
}

final StateNotifierProvider<ProfileController, ComplainantProfile>
    profileProvider =
    StateNotifierProvider<ProfileController, ComplainantProfile>(
  (Ref ref) => ProfileController(
    ref.watch(databaseProvider),
    ref.watch(initialProfileProvider),
  ),
);

// --- services -------------------------------------------------------------

final Provider<RecorderService> recorderProvider =
    Provider<RecorderService>((Ref ref) {
  final RecorderService service = RecorderService(
    calibrationOffsetDb: ref.read(settingsProvider).calibrationOffsetDb,
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Rebuilt when the OpenSky credentials change; the live community sources
/// need no key at all, which is why they are the primary path.
final Provider<FlightLookupService> flightLookupProvider =
    Provider<FlightLookupService>((Ref ref) {
  final http.Client client = ref.watch(httpClientProvider);
  final AppSettings settings = ref.watch(settingsProvider);

  final FlightLookupService service = FlightLookupService(
    liveSources: <AdsbSource>[
      Tar1090Source.adsbLol(client: client),
      Tar1090Source.airplanesLive(client: client),
    ],
    openSky: OpenSkySource(
      clientId: settings.openSkyClientId,
      clientSecret: settings.openSkyClientSecret,
      client: client,
    ),
  );
  ref.onDispose(service.stopTracking);
  return service;
});

final Provider<SnapService> snapServiceProvider =
    Provider<SnapService>((Ref ref) {
  final SnapService service = SnapService(
    database: ref.watch(databaseProvider),
    recorder: ref.watch(recorderProvider),
    lookup: ref.watch(flightLookupProvider),
    deviceInfo: ref.watch(deviceInfoProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

// --- live streams ---------------------------------------------------------

final StreamProvider<MeterReading> meterProvider = StreamProvider<MeterReading>(
    (Ref ref) => ref.watch(recorderProvider).meterStream);

final StreamProvider<CaptureProgress> captureProgressProvider =
    StreamProvider<CaptureProgress>(
        (Ref ref) => ref.watch(snapServiceProvider).progress);

// --- snap history ---------------------------------------------------------

/// The snap list is held in memory and written through to sqflite, rather than
/// re-queried on every change: the list is small, and the review screen needs
/// to update the moment a flight match lands.
class SnapListController extends StateNotifier<AsyncValue<List<Snap>>> {
  SnapListController(this._db) : super(const AsyncValue<List<Snap>>.loading()) {
    unawaited(refresh());
  }

  final AppDatabase _db;

  Future<void> refresh() async {
    try {
      state = AsyncValue<List<Snap>>.data(await _db.allSnaps());
    } on Object catch (e, s) {
      state = AsyncValue<List<Snap>>.error(e, s);
    }
  }

  /// Inserts or replaces one snap without a round trip to the database.
  void put(Snap snap) {
    final List<Snap> current = state.value ?? const <Snap>[];
    final List<Snap> next = <Snap>[
      snap,
      ...current.where((Snap s) => s.id != snap.id),
    ]..sort((Snap a, Snap b) => b.recordedAt.compareTo(a.recordedAt));
    state = AsyncValue<List<Snap>>.data(next);
  }

  void remove(String id) {
    final List<Snap> current = state.value ?? const <Snap>[];
    state = AsyncValue<List<Snap>>.data(
      current.where((Snap s) => s.id != id).toList(),
    );
  }
}

final StateNotifierProvider<SnapListController, AsyncValue<List<Snap>>>
    snapsProvider =
    StateNotifierProvider<SnapListController, AsyncValue<List<Snap>>>(
  (Ref ref) => SnapListController(ref.watch(databaseProvider)),
);

/// One snap by id, so the review screen keeps following it as matches arrive.
final ProviderFamily<Snap?, String> snapByIdProvider =
    Provider.family<Snap?, String>((Ref ref, String id) {
  final List<Snap> snaps = ref.watch(snapsProvider).value ?? const <Snap>[];
  for (final Snap snap in snaps) {
    if (snap.id == id) return snap;
  }
  return null;
});
