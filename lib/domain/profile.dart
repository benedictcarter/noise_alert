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
    this.email = '',
    this.phone = '',
  });

  final String fullName;
  final String addressLine1;
  final String addressLine2;
  final String town;
  final String postcode;

  /// Shown in the letter so replies reach the user even if the mail account
  /// they send from is a different one.
  final String email;
  final String phone;

  bool get isComplete =>
      fullName.trim().isNotEmpty &&
      postcode.trim().isNotEmpty &&
      email.trim().isNotEmpty;

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
    String? email,
    String? phone,
  }) =>
      ComplainantProfile(
        fullName: fullName ?? this.fullName,
        addressLine1: addressLine1 ?? this.addressLine1,
        addressLine2: addressLine2 ?? this.addressLine2,
        town: town ?? this.town,
        postcode: postcode ?? this.postcode,
        email: email ?? this.email,
        phone: phone ?? this.phone,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'fullName': fullName,
        'addressLine1': addressLine1,
        'addressLine2': addressLine2,
        'town': town,
        'postcode': postcode,
        'email': email,
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
          other.email == email &&
          other.phone == phone;

  @override
  int get hashCode => Object.hash(
        fullName,
        addressLine1,
        addressLine2,
        town,
        postcode,
        email,
        phone,
      );

  static ComplainantProfile fromJson(Map<String, Object?> json) =>
      ComplainantProfile(
        fullName: json['fullName'] as String? ?? '',
        addressLine1: json['addressLine1'] as String? ?? '',
        addressLine2: json['addressLine2'] as String? ?? '',
        town: json['town'] as String? ?? '',
        postcode: json['postcode'] as String? ?? '',
        email: json['email'] as String? ?? '',
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

  static const RecipientSet defaultSet = RecipientSet(
    id: 'default',
    label: 'Default',
    to: <String>['benedict.carter@gmail.com'],
  );
}
