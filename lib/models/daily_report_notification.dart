import '../utils/cameroon_time.dart';

class DailyReportNotification {
  final String id;
  final String recipientUserId;
  final String type; // "a_faire" | "a_corriger" | "a_valider" | "valide"
  final String message;
  final String? relatedReportId;
  final bool isRead;
  final DateTime createdAt;

  DailyReportNotification({
    required this.id,
    required this.recipientUserId,
    required this.type,
    required this.message,
    this.relatedReportId,
    this.isRead = false,
    required this.createdAt,
  });

  factory DailyReportNotification.fromMap(Map<String, dynamic> map) {
    return DailyReportNotification(
      id: map['_id'] as String,
      recipientUserId: map['recipientUserId'] as String? ?? '',
      type: map['type'] as String? ?? '',
      message: map['message'] as String? ?? '',
      relatedReportId: map['relatedReportId'] as String?,
      isRead: map['isRead'] as bool? ?? false,
      createdAt:
          parseCameroonTime(map['createdAt']?.toString()) ?? DateTime.now(),
    );
  }
}

class NotificationListResult {
  final int unreadCount;
  final int totalCount;
  final List<DailyReportNotification> data;

  NotificationListResult({required this.unreadCount, this.totalCount = 0, required this.data});

  factory NotificationListResult.fromMap(Map<String, dynamic> map) {
    return NotificationListResult(
      unreadCount: (map['unreadCount'] as num?)?.toInt() ?? 0,
      totalCount: (map['totalCount'] as num?)?.toInt() ?? 0,
      data: (map['data'] as List<dynamic>? ?? [])
          .map((n) => DailyReportNotification.fromMap(n as Map<String, dynamic>))
          .toList(),
    );
  }
}
