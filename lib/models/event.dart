class Event {
  final String id;
  final String name;
  final String description;
  final DateTime eventDate;
  final String location;
  final String organizerId;
  final int capacity;
  final double ticketPrice;
  final String? gatekeeperId;
  final String? gatekeeperEmail;
  final DateTime createdAt;

  Event({
    required this.id,
    required this.name,
    required this.description,
    required this.eventDate,
    required this.location,
    required this.organizerId,
    required this.capacity,
    required this.ticketPrice,
    this.gatekeeperId,
    this.gatekeeperEmail,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'eventDate': eventDate,
      'location': location,
      'organizerId': organizerId,
      'capacity': capacity,
      'ticketPrice': ticketPrice,
      'gatekeeperId': gatekeeperId,
      'gatekeeperEmail': gatekeeperEmail,
      'createdAt': createdAt,
    };
  }

  factory Event.fromMap(String id, Map<String, dynamic> map) {
    return Event(
      id: id,
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      eventDate: (map['eventDate'] as dynamic)?.toDate() ?? DateTime.now(),
      location: map['location'] ?? '',
      organizerId: map['organizerId'] ?? '',
      capacity: _parseCapacity(map['capacity']),
      ticketPrice: (map['ticketPrice'] as num?)?.toDouble() ?? 0.0,
      gatekeeperId: map['gatekeeperId'],
      gatekeeperEmail: map['gatekeeperEmail'],
      createdAt: (map['createdAt'] as dynamic)?.toDate() ?? DateTime.now(),
    );
  }

  static int _parseCapacity(dynamic capacity) {
    if (capacity is int) {
      return capacity;
    }
    if (capacity is String) {
      return int.tryParse(capacity) ?? 0;
    }
    return 0;
  }

  // Copy with method for updates
  Event copyWith({
    String? id,
    String? name,
    String? description,
    DateTime? eventDate,
    String? location,
    String? organizerId,
    int? capacity,
    double? ticketPrice,
    String? gatekeeperId,
    String? gatekeeperEmail,
    DateTime? createdAt,
  }) {
    return Event(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      eventDate: eventDate ?? this.eventDate,
      location: location ?? this.location,
      organizerId: organizerId ?? this.organizerId,
      capacity: capacity ?? this.capacity,
      ticketPrice: ticketPrice ?? this.ticketPrice,
      gatekeeperId: gatekeeperId ?? this.gatekeeperId,
      gatekeeperEmail: gatekeeperEmail ?? this.gatekeeperEmail,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}