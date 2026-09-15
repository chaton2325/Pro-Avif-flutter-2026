import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/daily_report_notification.dart';
import '../models/user.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';

/// Notifications du module Rapport Journalier (maquette écran 08) — même code couleur que
/// le tableau de suivi (vert = validé, jaune = attention, gris = neutre).
class DailyReportNotificationsScreen extends StatefulWidget {
  final User user;

  const DailyReportNotificationsScreen({super.key, required this.user});

  @override
  State<DailyReportNotificationsScreen> createState() => _DailyReportNotificationsScreenState();
}

const _pageSize = 20;

class _DailyReportNotificationsScreenState extends State<DailyReportNotificationsScreen> {
  final MongoService _mongoService = MongoService();
  List<DailyReportNotification> _notifications = [];
  bool _isLoading = true;
  bool _loadingMore = false;
  int _totalCount = 0;

  bool get _hasMore => _notifications.length < _totalCount;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.user.id == null) return;
    setState(() => _isLoading = true);
    final result = await _mongoService.getNotifications(widget.user.id!, skip: 0, limit: _pageSize);
    if (!mounted) return;
    setState(() {
      _notifications = result.data;
      _totalCount = result.totalCount;
      _isLoading = false;
    });
  }

  Future<void> _loadMore() async {
    if (widget.user.id == null || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final result = await _mongoService.getNotifications(
      widget.user.id!,
      skip: _notifications.length,
      limit: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _notifications = [..._notifications, ...result.data];
      _totalCount = result.totalCount;
      _loadingMore = false;
    });
  }

  Color _typeColor(String type) => switch (type) {
    'valide' => DailyReportColors.green600,
    'a_corriger' => DailyReportColors.yellow600,
    'a_valider' => DailyReportColors.yellow600,
    _ => Colors.grey.shade500,
  };

  IconData _typeIcon(String type) => switch (type) {
    'valide' => Icons.check_circle_rounded,
    'a_corriger' => Icons.error_outline_rounded,
    'a_valider' => Icons.hourglass_top_rounded,
    _ => Icons.notifications_none_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar('Notifications'),
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
                            child: Column(
                              children: [
                                Icon(Icons.notifications_off_outlined, size: 40, color: Colors.grey.shade400),
                                const SizedBox(height: 10),
                                Text('Aucune notification', style: TextStyle(color: Colors.grey.shade500)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _notifications.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == _notifications.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: _loadingMore
                                  ? const CircularProgressIndicator(color: DailyReportColors.green700)
                                  : OutlinedButton(
                                      onPressed: _loadMore,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: DailyReportColors.green700,
                                        side: const BorderSide(color: DailyReportColors.green600),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      child: Text('Charger plus (${_totalCount - _notifications.length} restantes)'),
                                    ),
                            ),
                          );
                        }
                        final n = _notifications[i];
                        final color = _typeColor(n.type);
                        return DailyReportCard(
                          accentColor: color,
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          children: [
                            InkWell(
                              onTap: () {
                                if (!n.isRead) {
                                  setState(() {});
                                  _mongoService.markNotificationRead(n.id);
                                }
                              },
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
                                    child: Icon(_typeIcon(n.type), color: color, size: 17),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          n.message,
                                          style: TextStyle(
                                            fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w800,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          DateFormat('dd/MM · HH:mm').format(n.createdAt),
                                          style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!n.isRead)
                                    Container(
                                      width: 8,
                                      height: 8,
                                      margin: const EdgeInsets.only(top: 4),
                                      decoration: const BoxDecoration(color: DailyReportColors.yellow500, shape: BoxShape.circle),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
    );
  }
}
