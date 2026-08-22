import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

// OUTBOUND: none directly. This is the client the three files beside it use.

/// The app's single HTTP client, so every outbound call in `lib/net/` shares
/// one connection pool and one place to be swapped for a fake in tests.
///
/// It lives here rather than in `providers.dart` so that `package:http` is
/// imported nowhere outside this directory: grep for it and you have found
/// every line that can reach the network.
/// Named so the rest of the app can hold the client without importing
/// `package:http` itself.
typedef NetClient = http.Client;

final Provider<http.Client> httpClientProvider =
    Provider<http.Client>((Ref ref) {
  final http.Client client = http.Client();
  ref.onDispose(client.close);
  return client;
});
