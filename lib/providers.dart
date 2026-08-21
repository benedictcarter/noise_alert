import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'core/device_info.dart';
import 'core/quick_snap.dart';
import 'data/audio/recorder_service.dart';
import 'data/flights/adsb_source.dart';
import 'data/flights/flight_lookup_service.dart';
import 'data/flights/opensky_source.dart';
import 'data/flights/tar1090_source.dart';
import 'data/map/map_image_service.dart';
import 'data/postcode/postcode_service.dart';
import 'data/snap_service.dart';
import 'data/storage/database.dart';
import 'domain/aircraft.dart';
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

/// Home-screen widget taps. Created once for the app's lifetime so a tap that
/// arrives while the snap screen is being rebuilt is not lost.
final Provider<QuickSnapChannel> quickSnapProvider =
    Provider<QuickSnapChannel>((Ref ref) {
  final QuickSnapChannel channel = QuickSnapChannel();
  ref.onDispose(channel.dispose);
  return channel;
});

/// False until there is a name and a postcode to write a complaint with.
///
/// Seeded from the stored profile rather than from a "have they seen it" flag,
/// so an install that already has details never sees the welcome screen, and
/// one that somehow lost them gets asked again instead of failing at the end
/// of a recording. Not persisted: it is a question the profile can always
/// answer.
final StateProvider<bool> onboardedProvider = StateProvider<bool>(
  (Ref ref) => ref.read(initialProfileProvider).isComplete,
);

/// Turns a postcode into a town, on the My details screen and nowhere else.
///
/// Shares the app's one HTTP client rather than opening a second: the lookup
/// happens at most a handful of times in the life of an install.
final Provider<PostcodeService> postcodeServiceProvider =
    Provider<PostcodeService>(
  (Ref ref) => PostcodeService(client: ref.watch(httpClientProvider)),
);

final Provider<DeviceInfoService> deviceInfoProvider =
    Provider<DeviceInfoService>((Ref ref) => DeviceInfoService());

// === settings and profile ===

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

// === services ===

final Provider<RecorderService> recorderProvider =
    Provider<RecorderService>((Ref ref) {
  final RecorderService service = RecorderService();
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

/// Draws the picture attached to the complaint.
///
/// Kept for the app's lifetime rather than rebuilt with the snap service: the
/// hidden map registers itself here once, at startup, and a service replaced
/// underneath it would take the picture away with it.
final Provider<MapImageService> mapImageProvider =
    Provider<MapImageService>((Ref ref) => MapImageService());

final Provider<SnapService> snapServiceProvider =
    Provider<SnapService>((Ref ref) {
  final SnapService service = SnapService(
    database: ref.watch(databaseProvider),
    recorder: ref.watch(recorderProvider),
    lookup: ref.watch(flightLookupProvider),
    deviceInfo: ref.watch(deviceInfoProvider),
    mapImages: ref.watch(mapImageProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

// === live streams ===

final StreamProvider<MeterReading> meterProvider = StreamProvider<MeterReading>(
    (Ref ref) => ref.watch(recorderProvider).meterStream);

final StreamProvider<CaptureProgress> captureProgressProvider =
    StreamProvider<CaptureProgress>(
        (Ref ref) => ref.watch(snapServiceProvider).progress);

/// Aircraft the rolling cache is currently holding, for the live map.
///
/// A view of the polls the matcher is already making, not a second source of
/// them. Seeded with what the cache holds at the moment of subscription so the
/// map is not blank for the three seconds until the next poll lands.
final StreamProvider<List<AircraftTrack>> liveTracksProvider =
    StreamProvider<List<AircraftTrack>>((Ref ref) {
  final FlightLookupService lookup = ref.watch(flightLookupProvider);
  return Stream<List<AircraftTrack>>.value(lookup.tracks)
      .followedBy(lookup.trackStream);
});

extension _Seeded<T> on Stream<T> {
  Stream<T> followedBy(Stream<T> rest) async* {
    yield* this;
    yield* rest;
  }
}

// === snap history ===

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
