/// QR Code Service for ticket encoding and decoding
class QrCodeService {
  /// Generate QR code data for a ticket
  /// Encodes: ticketId|eventId|attendeeId
  static String generateQrCodeData({
    required String ticketId,
    required String eventId,
    required String attendeeId,
  }) {
    return '$ticketId|$eventId|$attendeeId';
  }

  /// Parse QR code data to extract ticket information
  static Map<String, String>? parseQrCodeData(String qrData) {
    try {
      List<String> parts = qrData.split('|');
      if (parts.length != 3) {
        return null;
      }

      return {
        'ticketId': parts[0],
        'eventId': parts[1],
        'attendeeId': parts[2],
      };
    } catch (e) {
      return null;
    }
  }

  /// Validate QR code format
  static bool isValidQrCodeFormat(String qrData) {
    try {
      List<String> parts = qrData.split('|');
      return parts.length == 3 && 
             parts[0].isNotEmpty && 
             parts[1].isNotEmpty && 
             parts[2].isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}
