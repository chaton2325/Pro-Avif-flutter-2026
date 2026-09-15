import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/farm_daily_report.dart';
import '../models/user.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import 'login_screen.dart';
import 'validator_report_detail_screen.dart';

/// Tableau de suivi du validateur (maquette écran 09) : synthèse du jour + une ligne par
/// ferme, mis à jour en temps réel côté serveur (GET /daily-reports?date=).
class ValidatorOverviewScreen extends StatefulWidget {
  final User user;

  const ValidatorOverviewScreen({super.key, required this.user});

  @override
  State<ValidatorOverviewScreen> createState() => _ValidatorOverviewScreenState();
}

class _ValidatorOverviewScreenState extends State<ValidatorOverviewScreen> {
  final MongoService _mongoService = MongoService();
  FarmReportOverview? _overview;
  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();

  String get _selectedDateStr => DateFormat('yyyy-MM-dd').format(_selectedDate);
  bool get _isToday => _selectedDateStr == DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final overview = await _mongoService.getDailyReportsOverview(_selectedDateStr);
    if (!mounted) return;
    setState(() {
      _overview = overview;
      _isLoading = false;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _load();
    }
  }

  void _logout() {
    _mongoService.logout();
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  Future<void> _openFarm(FarmReportOverviewItem item) async {
    if (item.status == 'non_fait') return;
    final report = await _mongoService.getOrCreateTodayReport(farmId: item.farmId, date: _selectedDateStr);
    if (report == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ValidatorReportDetailScreen(user: widget.user, report: report)),
    );
    _load();
  }

  Color _statusPillColor(String status) => switch (status) {
    'valide' => DailyReportColors.green600,
    'en_attente_validation' => DailyReportColors.yellow500,
    'a_corriger' => DailyReportColors.yellow500,
    'brouillon' => DailyReportColors.grey500,
    _ => DailyReportColors.green900,
  };

  String _actionLabel(String status) => switch (status) {
    'en_attente_validation' => 'Valider',
    'a_corriger' => 'Relancer',
    'valide' => 'Consulter',
    'brouillon' => 'En cours',
    _ => 'Relancer',
  };

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    final aValider = overview?.farms.where((f) => f.status == 'en_attente_validation').length ?? 0;
    final nonFait = overview?.farms.where((f) => f.status == 'non_fait').length ?? 0;
    final valides = overview?.farms.where((f) => f.status == 'valide').length ?? 0;

    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: AppBar(
        backgroundColor: DailyReportColors.green900,
        foregroundColor: Colors.white,
        title: const Text('Suivi des rapports'),
        actions: [
          IconButton(icon: const Icon(Icons.calendar_today, size: 20), onPressed: _pickDate, tooltip: 'Choisir une date'),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout, tooltip: 'Déconnexion'),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Text(
                        '${DateFormat('dd/MM/yyyy').format(_selectedDate)}${_isToday ? " (aujourd'hui)" : ""} · ${overview?.farms.length ?? 0} fermes',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                      const Spacer(),
                      if (!_isToday)
                        TextButton(
                          onPressed: () {
                            setState(() => _selectedDate = DateTime.now());
                            _load();
                          },
                          child: const Text("Revenir à aujourd'hui", style: TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _statBox('$aValider', 'À valider', DailyReportColors.yellow600)),
                      const SizedBox(width: 8),
                      Expanded(child: _statBox('$nonFait', 'Non fait', Colors.grey.shade600)),
                      const SizedBox(width: 8),
                      Expanded(child: _statBox('$valides', 'Validés', DailyReportColors.green700)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  for (final f in overview?.farms ?? []) _farmRow(f),
                ],
              ),
            ),
    );
  }

  Widget _statBox(String value, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: color)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _farmRow(FarmReportOverviewItem f) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: ListTile(
        onTap: () => _openFarm(f),
        title: Text(f.farmName, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('Lot ${f.lotNumber ?? "—"}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _statusPillColor(f.status).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                f.statusLabel.toUpperCase(),
                style: TextStyle(color: _statusPillColor(f.status), fontWeight: FontWeight.w800, fontSize: 10),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _actionLabel(f.status),
              style: const TextStyle(color: DailyReportColors.green700, fontWeight: FontWeight.w800, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
