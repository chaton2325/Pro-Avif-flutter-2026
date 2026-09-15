import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/daily_report_notification.dart';
import '../models/user.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';

/// Notifications du module Rapport Journalier (maquette écran 08) — même code couleur que
/// le tableau de suivi (vert = validé, jaune = attention, gris = neutre).
class DailyReportNotificationsScreen extends StatefulWidget {
  final User user;

  const DailyReportNotificationsScreen({super.key, required this.user});

  @override
  State<DailyReportNotificationsScreen> createState() => _DailyReportNotificationsScreenState();
}

class _DailyReportNotificationsScreenState extends State<DailyReportNotificationsScreen> {
  final MongoService _mongoService = MongoService();
  List<DailyReportNotification> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.user.id == null) return;
    setState(() => _isLoading = true);
    final result = await _mongoService.getNotifications(widget.user.id!);
    if (!mounted) return;
    setState(() {
      _notifications = result.data;
      _isLoading = false;
    });
  }

  Color _dotColor(String type) => switch (type) {
    'valide' => DailyReportColors.green600,
    'a_corriger' => DailyReportColors.yellow500,
    'a_valider' => DailyReportColors.yellow500,
    _ => Colors.grey.shade400,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: AppBar(
        backgroundColor: DailyReportColors.green900,
        foregroundColor: Colors.white,
        title: const Text('Notifications'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
          : RefreshIndicator(
              onRefresh: _load,
              child: _notifications.isEmpty
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 60),
                          child: Center(
                            child: Text('Aucune notification', style: TextStyle(color: Colors.grey.shade500)),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _notifications.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final n = _notifications[i];
                        return ListTile(
                          onTap: () {
                            if (!n.isRead) _mongoService.markNotificationRead(n.id);
                          },
                          leading: Container(
                            margin: const EdgeInsets.only(top: 6),
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(color: _dotColor(n.type), shape: BoxShape.circle),
                          ),
                          title: Text(
                            n.message,
                            style: TextStyle(
                              fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            DateFormat('dd/MM · HH:mm').format(n.createdAt),
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
