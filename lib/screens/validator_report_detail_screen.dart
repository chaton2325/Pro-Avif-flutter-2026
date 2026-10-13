import 'package:flutter/material.dart';
import '../models/farm_daily_report.dart';
import '../models/user.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/blocking_loader.dart';
import '../widgets/daily_report_full_summary.dart';
import '../widgets/daily_report_widgets.dart';

const List<String> kRejectReasonChips = [
  'Chiffre incohérent',
  'Stock à vérifier',
  'Photo manquante',
];

/// Catégories flagables par salle — un motif texte libre ne dit pas AU RÉDACTEUR quel chiffre
/// précis revoir ; ces flags si (ex: "salle 1 · PO") s'affichent ensuite sur son rapport.
const List<({String field, String label})> kRoomFlagFields = [
  (field: 'mortality', label: 'Mortalité'),
  (field: 'consumption', label: 'Consommation'),
  (field: 'oac', label: 'OAC'),
  (field: 'po', label: 'PO'),
  (field: 'dj', label: 'DJ'),
  (field: 'cas', label: 'CAS'),
  (field: 'sal', label: 'SAL'),
];

/// Catégories flagables non liées à une salle précise. Pas de "Transferts" ici : c'est
/// réservé à l'admin (voir AdminRoomTransfersScreen), le rédacteur qui corrige un rapport
/// "à corriger" n'a aucun moyen d'agir dessus.
const List<({String field, String label})> kGlobalFlagFields = [
  (field: 'water', label: 'Eau'),
  (field: 'treatments', label: 'Traitements'),
  (field: 'staff', label: 'Personnel'),
  (field: 'observation', label: 'Observation'),
];

/// Détail & validation (maquette écran 10) : données du rédacteur en lecture seule, un
/// renvoi impose un motif (chip ou "Autre" + texte), jamais de refus sans justification.
class ValidatorReportDetailScreen extends StatefulWidget {
  final User user;
  final FarmDailyReport report;

  const ValidatorReportDetailScreen({super.key, required this.user, required this.report});

  @override
  State<ValidatorReportDetailScreen> createState() => _ValidatorReportDetailScreenState();
}

class _ValidatorReportDetailScreenState extends State<ValidatorReportDetailScreen> {
  final MongoService _mongoService = MongoService();
  late FarmDailyReport _report;
  String? _selectedReason;
  final _customReasonController = TextEditingController();
  bool _busy = false;
  String? _error;
  // Clé composite "salle|champ" (salle vide pour un flag global) — un Set suffit, pas besoin
  // d'égalité sur RejectionFlag lui-même.
  final Set<String> _selectedFlagKeys = {};
  // Bâtiment en production ? Sinon on ne propose pas de flagger OAC/PO/DJ/CAS/SAL (rien à
  // corriger là, le rédacteur n'a pas de saisie de production pour ce bâtiment).
  bool _isProduction = true;

  static const _productionFields = {'oac', 'po', 'dj', 'cas', 'sal'};

  @override
  void initState() {
    super.initState();
    _report = widget.report;
    _loadFarm();
  }

  Future<void> _loadFarm() async {
    final farm = await _mongoService.getFarmById(_report.farmId);
    if (!mounted || farm == null) return;
    setState(() => _isProduction = farm.isProduction);
  }

  List<({String field, String label})> get _roomFlagFields => kRoomFlagFields
      .where((f) => _isProduction || !_productionFields.contains(f.field))
      .toList();

  bool get _canAct => _report.status == 'en_attente_validation';

  String _flagKey(String? room, String field) => '${room ?? ''}|$field';

  void _toggleFlag(String? room, String field) {
    final key = _flagKey(room, field);
    setState(() {
      if (!_selectedFlagKeys.remove(key)) _selectedFlagKeys.add(key);
    });
  }

  List<RejectionFlag> _buildFlags() {
    final flags = <RejectionFlag>[];
    for (final room in _report.startCounts) {
      for (final f in kRoomFlagFields) {
        if (_selectedFlagKeys.contains(_flagKey(room.roomName, f.field))) {
          flags.add(RejectionFlag(roomName: room.roomName, field: f.field, label: f.label));
        }
      }
    }
    for (final f in kGlobalFlagFields) {
      if (_selectedFlagKeys.contains(_flagKey(null, f.field))) {
        flags.add(RejectionFlag(field: f.field, label: f.label));
      }
    }
    return flags;
  }

  Future<bool> _confirm(String title, String content, {required Color color, required String confirmLabel}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        content: Text(content, style: const TextStyle(fontSize: 13.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _validate() async {
    final confirmed = await _confirm(
      'Valider ce rapport ?',
      'Êtes-vous sûr de vouloir valider le rapport de ${_report.farmName} du ${_report.date} ? '
          "Cette action est définitive — le rapport ne pourra plus être modifié.",
      color: DailyReportColors.green700,
      confirmLabel: 'Valider',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await runBlocking(context, () => _mongoService.validateDailyReport(_report.id));
    if (!mounted) return;
    if (result.error != null) {
      setState(() {
        _busy = false;
        _error = result.error;
      });
      return;
    }
    Navigator.pop(context);
  }

  Future<void> _reject() async {
    final reason = _selectedReason == 'Autre…' ? _customReasonController.text.trim() : _selectedReason;
    if (reason == null || reason.isEmpty) {
      setState(() => _error = 'Choisissez ou saisissez un motif.');
      return;
    }
    final flags = _buildFlags();
    if (flags.isEmpty) {
      setState(() => _error = "Précisez au moins un endroit à corriger (ex : salle 1 · PO).");
      return;
    }
    final confirmed = await _confirm(
      'Renvoyer ce rapport ?',
      "Êtes-vous sûr de vouloir renvoyer le rapport de ${_report.farmName} à corriger ? "
          "Le rédacteur recevra le motif et les endroits précis sélectionnés.",
      color: DailyReportColors.yellow600,
      confirmLabel: 'Renvoyer',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await runBlocking(context, () => _mongoService.rejectDailyReport(_report.id, reason, flags: flags));
    if (!mounted) return;
    if (result.error != null) {
      setState(() {
        _busy = false;
        _error = result.error;
      });
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar('${_report.farmName} — Lot ${_report.lotNumber ?? "—"}'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DailyReportFullSummary(report: _report, isProduction: _isProduction),
          const SizedBox(height: 16),
          if (_canAct) ...[
            const DailyReportSectionLabel('Renvoyer — motif', icon: Icons.reply_rounded),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [...kRejectReasonChips, 'Autre…'].map((reason) {
                final selected = _selectedReason == reason;
                return ChoiceChip(
                  label: Text(reason),
                  selected: selected,
                  selectedColor: DailyReportColors.yellow500,
                  labelStyle: TextStyle(fontSize: 12, color: selected ? Colors.black87 : Colors.black54),
                  onSelected: (_) => setState(() => _selectedReason = reason),
                );
              }).toList(),
            ),
            if (_selectedReason == 'Autre…') ...[
              const SizedBox(height: 8),
              TextField(
                controller: _customReasonController,
                decoration: const InputDecoration(hintText: 'Précisez le motif', border: OutlineInputBorder()),
              ),
            ],
            const SizedBox(height: 16),
            const DailyReportSectionLabel("Renvoyer — endroit(s) précis à corriger", icon: Icons.my_location_rounded),
            for (final room in _report.startCounts) _roomFlagPicker(room.roomName),
            const Text('Général', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: kGlobalFlagFields.map((f) {
                final selected = _selectedFlagKeys.contains(_flagKey(null, f.field));
                return ChoiceChip(
                  label: Text(f.label),
                  selected: selected,
                  selectedColor: Colors.red.shade600,
                  labelStyle: TextStyle(fontSize: 11.5, color: selected ? Colors.white : Colors.black87, fontWeight: FontWeight.w700),
                  onSelected: (_) => _toggleFlag(null, f.field),
                );
              }).toList(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DailyReportColors.yellow600,
                        side: const BorderSide(color: DailyReportColors.yellow500, width: 1.4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _busy ? null : _reject,
                      child: const Text('Renvoyer', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(colors: [DailyReportColors.green700, DailyReportColors.green600]),
                      boxShadow: [
                        BoxShadow(color: DailyReportColors.green700.withValues(alpha: 0.32), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _busy ? null : _validate,
                        child: Center(
                          child: _busy
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Valider', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: DailyReportColors.green100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: DailyReportColors.green700, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    'Statut : ${_report.statusLabel}',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: DailyReportColors.green900),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _roomFlagPicker(String roomName) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(roomName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _roomFlagFields.map((f) {
              final selected = _selectedFlagKeys.contains(_flagKey(roomName, f.field));
              return ChoiceChip(
                label: Text(f.label),
                selected: selected,
                selectedColor: Colors.red.shade600,
                labelStyle: TextStyle(fontSize: 11.5, color: selected ? Colors.white : Colors.black87, fontWeight: FontWeight.w700),
                onSelected: (_) => _toggleFlag(roomName, f.field),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
