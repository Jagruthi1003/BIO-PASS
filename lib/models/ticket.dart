class Ticket {
  final String id;
  final String eventId;
  final String attendeeId;
  final String attendeeName;
  final String attendeeEmail;
  final double ticketPrice;
  final String? facialFeatures; // Base64 encoded JSON string instead of raw landmarks
  final String? zkProof; // SHA-256 hash of normalized landmarks
  final String? normalizedLandmarksEncrypted; // AES-256 encrypted normalized landmarks
  final String status; // 'ACTIVE', 'USED', 'CANCELLED'
  final DateTime createdAt;
  final DateTime? entryTimestamp; // When ticket was marked as USED
  final String? verifiedBy; // Gatekeeper UID who verified entry
  final double? euclideanDistance; // Distance metric from face verification
  final String? verificationMessage;
  final bool? legacyIsVerified;
  final String? legacyRegistrationStatus;

  Ticket({
    required this.id,
    required this.eventId,
    required this.attendeeId,
    required this.attendeeName,
    required this.attendeeEmail,
    required this.ticketPrice,
    this.facialFeatures,
    this.zkProof,
    this.normalizedLandmarksEncrypted,
    required this.status,
    required this.createdAt,
    this.entryTimestamp,
    this.verifiedBy,
    this.euclideanDistance,
    this.verificationMessage,
    this.legacyIsVerified,
    this.legacyRegistrationStatus,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'eventId': eventId,
      'attendeeId': attendeeId,
      'attendeeName': attendeeName,
      'attendeeEmail': attendeeEmail,
      'ticketPrice': ticketPrice,
      'facialFeatures': facialFeatures,
      'zkProof': zkProof,
      'normalizedLandmarksEncrypted': normalizedLandmarksEncrypted,
      'status': status,
      'createdAt': createdAt,
      'entryTimestamp': entryTimestamp,
      'verifiedBy': verifiedBy,
      'euclideanDistance': euclideanDistance,
      'verificationMessage': verificationMessage,
      'isVerified': legacyIsVerified ?? isVerified,
      'registrationStatus': legacyRegistrationStatus ?? registrationStatus,
      'usedAt': usedAt,
      'isRegistered': isRegistered,
    };
  }

  factory Ticket.fromMap(String id, Map<String, dynamic> map) {
    return Ticket(
      id: id,
      eventId: map['eventId'] ?? '',
      attendeeId: map['attendeeId'] ?? '',
      attendeeName: map['attendeeName'] ?? '',
      attendeeEmail: map['attendeeEmail'] ?? '',
      ticketPrice: (map['ticketPrice'] as num?)?.toDouble() ?? 0.0,
      facialFeatures: map['facialFeatures'],
      zkProof: map['zkProof'],
      normalizedLandmarksEncrypted: map['normalizedLandmarksEncrypted'],
      status: map['status'] ?? 'ACTIVE',
      createdAt: (map['createdAt'] as dynamic)?.toDate() ?? DateTime.now(),
      entryTimestamp: (map['entryTimestamp'] as dynamic)?.toDate(),
      verifiedBy: map['verifiedBy'],
      euclideanDistance: (map['euclideanDistance'] as num?)?.toDouble(),
      verificationMessage: map['verificationMessage'],
      legacyIsVerified: map['isVerified'] as bool?,
      legacyRegistrationStatus: map['registrationStatus'] as String?,
    );
  }

  // Copy with method for updates
  Ticket copyWith({
    String? id,
    String? eventId,
    String? attendeeId,
    String? attendeeName,
    String? attendeeEmail,
    double? ticketPrice,
    String? facialFeatures,
    String? zkProof,
    String? normalizedLandmarksEncrypted,
    String? status,
    DateTime? createdAt,
    DateTime? entryTimestamp,
    String? verifiedBy,
    double? euclideanDistance,
    String? verificationMessage,
    bool? legacyIsVerified,
    String? legacyRegistrationStatus,
    bool? isVerified,
    String? registrationStatus,
  }) {
    return Ticket(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      attendeeId: attendeeId ?? this.attendeeId,
      attendeeName: attendeeName ?? this.attendeeName,
      attendeeEmail: attendeeEmail ?? this.attendeeEmail,
      ticketPrice: ticketPrice ?? this.ticketPrice,
      facialFeatures: facialFeatures ?? this.facialFeatures,
      zkProof: zkProof ?? this.zkProof,
      normalizedLandmarksEncrypted: normalizedLandmarksEncrypted ?? this.normalizedLandmarksEncrypted,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      entryTimestamp: entryTimestamp ?? this.entryTimestamp,
      verifiedBy: verifiedBy ?? this.verifiedBy,
      euclideanDistance: euclideanDistance ?? this.euclideanDistance,
      verificationMessage: verificationMessage ?? this.verificationMessage,
      legacyIsVerified:
          legacyIsVerified ?? isVerified ?? this.legacyIsVerified,
      legacyRegistrationStatus: legacyRegistrationStatus ??
          registrationStatus ??
          this.legacyRegistrationStatus,
    );
  }

  bool get isVerified => status == 'USED' || (legacyIsVerified ?? false);

  bool get isRegistered =>
      zkProof != null ||
      normalizedLandmarksEncrypted != null ||
      ((legacyRegistrationStatus ?? '').isNotEmpty &&
          legacyRegistrationStatus != 'pending');

  DateTime? get usedAt => entryTimestamp;

  String get registrationStatus {
    if (legacyRegistrationStatus != null &&
        legacyRegistrationStatus!.isNotEmpty) {
      return legacyRegistrationStatus!;
    }
    if (status == 'USED') return 'verified';
    if (status == 'CANCELLED') return 'cancelled';
    return isRegistered ? 'registered' : 'pending';
  }
}
