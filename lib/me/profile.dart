/// Order-sensitive element comparison, so the domain layer stays pure Dart
/// rather than pulling in `package:flutter/foundation.dart` for one function.
bool listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The complainant's details.
///
/// Stored in the app's private database on the device and nowhere else. It is
/// written into the body of an email that the user sends from their own mail
/// account, so no server of ours ever holds it.
class ComplainantProfile {
  const ComplainantProfile({
    this.fullName = '',
    this.addressLine1 = '',
    this.addressLine2 = '',
    this.town = '',
    this.postcode = '',
    this.phone = '',
  });

  final String fullName;
  final String addressLine1;
  final String addressLine2;
  final String town;
  final String postcode;
  final String phone;

  /// Everything a complaint actually requires.
  ///
  /// A name and a postcode, and nothing else. The house number and street are
  /// welcome but not demanded: a council can act on "someone in TW6 1AP" and
  /// the point of this app is that a person who is annoyed by a jet can say so
  /// without first completing a form. No email address is asked for either --
  /// the letter is sent from the user's own mail account, so the reply address
  /// travels with it whether we print it or not.
  bool get isComplete =>
      fullName.trim().isNotEmpty && postcode.trim().isNotEmpty;

  List<String> get addressLines => <String>[
        if (addressLine1.trim().isNotEmpty) addressLine1.trim(),
        if (addressLine2.trim().isNotEmpty) addressLine2.trim(),
        if (town.trim().isNotEmpty) town.trim(),
        if (postcode.trim().isNotEmpty) postcode.trim(),
      ];

  String get addressBlock => addressLines.join('\n');
  String get addressOneLine => addressLines.join(', ');

  ComplainantProfile copyWith({
    String? fullName,
    String? addressLine1,
    String? addressLine2,
    String? town,
    String? postcode,
    String? phone,
  }) =>
      ComplainantProfile(
        fullName: fullName ?? this.fullName,
        addressLine1: addressLine1 ?? this.addressLine1,
        addressLine2: addressLine2 ?? this.addressLine2,
        town: town ?? this.town,
        postcode: postcode ?? this.postcode,
        phone: phone ?? this.phone,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'fullName': fullName,
        'addressLine1': addressLine1,
        'addressLine2': addressLine2,
        'town': town,
        'postcode': postcode,
        'phone': phone,
      };

  /// Value equality matters here beyond tidiness: `StateNotifier` only tells
  /// its listeners about a new state when `state != newState`, so without this
  /// every keystroke in the settings form would rebuild every consumer.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComplainantProfile &&
          other.fullName == fullName &&
          other.addressLine1 == addressLine1 &&
          other.addressLine2 == addressLine2 &&
          other.town == town &&
          other.postcode == postcode &&
          other.phone == phone;

  @override
  int get hashCode => Object.hash(
        fullName,
        addressLine1,
        addressLine2,
        town,
        postcode,
        phone,
      );

  static ComplainantProfile fromJson(Map<String, Object?> json) =>
      ComplainantProfile(
        fullName: json['fullName'] as String? ?? '',
        addressLine1: json['addressLine1'] as String? ?? '',
        addressLine2: json['addressLine2'] as String? ?? '',
        town: json['town'] as String? ?? '',
        postcode: json['postcode'] as String? ?? '',
        // 'email' appears in rows written before the field was dropped. Read
        // past it: the letter is sent from the user's own mail account, so it
        // was never doing anything the reply-to header did not already do.
        phone: json['phone'] as String? ?? '',
      );
}

/// Who a complaint goes to.
class RecipientSet {
  const RecipientSet({
    required this.id,
    required this.label,
    this.to = const <String>[],
    this.cc = const <String>[],
    this.bcc = const <String>[],
  });

  final String id;
  final String label;
  final List<String> to;
  final List<String> cc;

  /// A BCC to the user's own address, or to the flight-watch group's shared
  /// mailbox, is how a durable collated record gets built without anyone
  /// running a database of personal details.
  final List<String> bcc;

  RecipientSet copyWith({
    String? label,
    List<String>? to,
    List<String>? cc,
    List<String>? bcc,
  }) =>
      RecipientSet(
        id: id,
        label: label ?? this.label,
        to: to ?? this.to,
        cc: cc ?? this.cc,
        bcc: bcc ?? this.bcc,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'label': label,
        'to': to,
        'cc': cc,
        'bcc': bcc,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecipientSet &&
          other.id == id &&
          other.label == label &&
          listEquals(other.to, to) &&
          listEquals(other.cc, cc) &&
          listEquals(other.bcc, bcc);

  @override
  int get hashCode => Object.hash(
        id,
        label,
        Object.hashAll(to),
        Object.hashAll(cc),
        Object.hashAll(bcc),
      );

  static RecipientSet fromJson(Map<String, Object?> json) => RecipientSet(
        id: json['id'] as String,
        label: json['label'] as String? ?? '',
        to: ((json['to'] as List<Object?>?) ?? const <Object?>[])
            .cast<String>(),
        cc: ((json['cc'] as List<Object?>?) ?? const <Object?>[])
            .cast<String>(),
        bcc: ((json['bcc'] as List<Object?>?) ?? const <Object?>[])
            .cast<String>(),
      );

  /// The Flightpath Watch group mailbox, copied on every complaint by default.
  ///
  /// CC rather than BCC: the recipient should be able to see that the group has
  /// the complaint too, and the sender should be able to remove it.
  static const String flightpathWatchCc = 'info@flightpathwatch.co.uk';

  /// Where a complaint goes when nobody has opened Settings.
  ///
  /// The `to:` address is a personal inbox on purpose. The beta is two parties,
  /// Ben and Flightpath Watch, and both of them are in this list knowingly, so
  /// a default that mails them is a default that mails the only people there
  /// are. It stops being that the moment there is a third user: a stranger who
  /// never opens Settings would be sending their name, their address, the
  /// coordinates of their house and a recording made inside it to somebody
  /// else's personal Gmail, without ever being shown where it went.
  ///
  /// So this address goes when the beta group expands, and it goes by removal
  /// rather than replacement: ship no default `to:` at all and make the first
  /// send ask, because a wrong default is invisible in a way a missing one is
  /// not. See TODO.md, "Decide the default recipient".
  static const RecipientSet defaultSet = RecipientSet(
    id: 'default',
    label: 'Default',
    to: <String>['benedict.carter@gmail.com'],
    cc: <String>[flightpathWatchCc],
  );

  /// Adds [flightpathWatchCc] to a set that predates it, and leaves any other
  /// set alone.
  ///
  /// Defaults only apply to installs that have never saved their settings, and
  /// this one arrived after the app shipped, so without a seeding pass the
  /// people already using the app would silently never copy the group.
  static RecipientSet seedGroupCc(RecipientSet set) =>
      set.id != 'default' || set.cc.contains(flightpathWatchCc)
          ? set
          : set.copyWith(cc: <String>[...set.cc, flightpathWatchCc]);
}
