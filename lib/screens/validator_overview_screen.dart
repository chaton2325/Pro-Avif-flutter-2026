import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/farm_daily_report.dart';
import '../models/user.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
import 'login_screen.dart';
import 'validator_report_detail_screen.dart';

enum _SortMode { alpha, status }

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
  final _searchController = TextEditingController();
  String _searchQuery = '';
  _SortMode _sortMode = _SortMode.alpha;

  String get _selectedDateStr => DateFormat('yyyy-MM-dd').format(_selectedDate);
  bool get _isToday => _selectedDateStr == DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<FarmReportOverviewItem> get _visibleFarms {
    var farms = _overview?.farms ?? <FarmReportOverviewItem>[];
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      farms = farms.where((f) => f.farmName.toLowerCase().contains(q)).toList();
    } else {
      farms = List.of(farms);
    }
    farms.sort((a, b) => _sortMode == _SortMode.alpha
        ? a.farmName.toLowerCase().compareTo(b.farmName.toLowerCase())
        : _statusPriority(a.status).compareTo(_statusPriority(b.status)));
    return farms;
  }

  int _statusPriority(String status) => switch (status) {
    'en_attente_validation' => 0,
    'a_corriger' => 1,
    'brouillon' => 2,
    'non_fait' => 3,
    'valide' => 4,
    _ => 5,
  };

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
    'en_attente_validation' => DailyReportColors.yellow600,
    'a_corriger' => DailyReportColors.yellow600,
    'brouillon' => DailyReportColors.green700,
    'non_fait' => Colors.grey.shade500,
    _ => Colors.grey.shade500,
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
      appBar: dailyReportAppBar(
        'Suivi des rapports',
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
                      Icon(Icons.event_note_rounded, size: 15, color: Colors.grey.shade500),
                      const SizedBox(width: 6),
                      Text(
                        '${DateFormat('dd/MM/yyyy').format(_selectedDate)}${_isToday ? " (aujourd'hui)" : ""} · ${overview?.farms.length ?? 0} fermes',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w600),
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
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: DailyReportStatTile(
                          value: '$aValider',
                          label: 'À valider',
                          color: DailyReportColors.yellow600,
                          icon: Icons.hourglass_top_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DailyReportStatTile(
                          value: '$nonFait',
                          label: 'Non fait',
                          color: Colors.grey.shade500,
                          icon: Icons.remove_circle_outline,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DailyReportStatTile(
                          value: '$valides',
                          label: 'Validés',
                          color: DailyReportColors.green700,
                          icon: Icons.check_circle_outline,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const DailyReportSectionLabel('Par bâtiment'),
                  DailySearchSortBar<_SortMode>(
                    controller: _searchController,
                    hintText: 'Rechercher un bâtiment…',
                    onSearchChanged: (v) => setState(() => _searchQuery = v),
                    sortValue: _sortMode,
                    onSortChanged: (v) => setState(() => _sortMode = v),
                    sortOptions: const [
                      DailySortOption(_SortMode.alpha, 'Alphabétique (A→Z)'),
                      DailySortOption(_SortMode.status, 'Statut (urgence)'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_visibleFarms.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                        child: Text('Aucun bâtiment trouvé.', style: TextStyle(color: Colors.grey.shade500)),
                      ),
                    )
                  else
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.2,
                      children: [for (final f in _visibleFarms) _farmCard(f)],
                    ),
                ],
              ),
            ),
    );
  }

  Widget _farmCard(FarmReportOverviewItem f) {
    final color = _statusPillColor(f.status);
    final enabled = f.status != 'non_fait';
    return DailyReportCard(
      accentColor: color,
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      children: [
        InkWell(
          onTap: enabled ? () => _openFarm(f) : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                f.farmName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                'Lot ${f.lotNumber ?? "—"}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
              ),
              const SizedBox(height: 6),
              DailyReportStatusBadge(label: f.statusLabel.toUpperCase(), color: color),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 32,
                child: ElevatedButton(
                  onPressed: enabled ? () => _openFarm(f) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: enabled ? color : Colors.grey.shade200,
                    disabledBackgroundColor: Colors.grey.shade200,
                    foregroundColor: enabled ? Colors.white : Colors.grey.shade500,
                    padding: EdgeInsets.zero,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                  ),
                  child: Text(_actionLabel(f.status), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
