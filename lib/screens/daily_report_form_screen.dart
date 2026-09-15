import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/farm_daily_report.dart';
import '../models/lot_headcount.dart';
import '../models/treatment_reference.dart';
import '../models/user.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import 'daily_report_summary_screen.dart';

const List<String> kStaffStatuses = ['present', 'repos', 'absent', 'malade', 'permission'];
const Map<String, String> kStaffStatusLabels = {
  'present': 'Présent',
  'repos': 'Repos',
  'absent': 'Absent',
  'malade': 'Malade',
  'permission': 'Permission',
};

/// Formulaire du rapport en 4 étapes (maquette écrans 03-06) : identification & effectifs
/// (lecture seule), aliment & mortalité, production & eau, traitements & personnel. Chaque
/// "Suivant" sauvegarde l'étape (PATCH) et recharge les champs AUTO recalculés côté serveur.
class DailyReportFormScreen extends StatefulWidget {
  final User user;
  final FarmDailyReport report;

  const DailyReportFormScreen({super.key, required this.user, required this.report});

  @override
  State<DailyReportFormScreen> createState() => _DailyReportFormScreenState();
}

class _DailyReportFormScreenState extends State<DailyReportFormScreen> {
  final MongoService _mongoService = MongoService();
  late FarmDailyReport _report;
  int _step = 0;
  bool _saving = false;
  String? _error;

  late List<RoomConsumptionEntry> _consumption;
  late List<RoomHeadcount> _mortality;
  late SexCount _clinicMortality;
  late List<RoomProduction> _production;
  double? _waterLiters;
  late List<TreatmentEntry> _treatments;
  late List<StaffStatusEntry> _staffStatuses;
  String? _observation;

  List<TreatmentReference> _references = [];
  bool _loadingRefs = true;

  static const _stepTitles = [
    'Identification & effectifs',
    'Aliment & mortalité',
    'Production & eau',
    'Traitements & personnel',
  ];

  @override
  void initState() {
    super.initState();
    _report = widget.report;
    _consumption = _report.startCounts
        .map((r) => _report.aliment.consumptionByRoom.firstWhere(
              (c) => c.roomName == r.roomName,
              orElse: () => RoomConsumptionEntry(roomName: r.roomName),
            ))
        .toList();
    _mortality = _report.startCounts
        .map((r) => _report.mortality.byRoom.firstWhere(
              (m) => m.roomName == r.roomName,
              orElse: () => RoomHeadcount(roomName: r.roomName),
            ))
        .toList();
    _clinicMortality = _report.mortality.clinic;
    _production = _report.startCounts
        .map((r) => _report.production.firstWhere(
              (p) => p.roomName == r.roomName,
              orElse: () => RoomProduction(roomName: r.roomName),
            ))
        .toList();
    _waterLiters = _report.waterLiters;
    _treatments = List.of(_report.treatments);
    _staffStatuses = List.of(_report.staffStatuses);
    _observation = _report.observation;
    _loadReferentials();
  }

  Future<void> _loadReferentials() async {
    final refs = await _mongoService.getTreatmentReferences();
    final staff = await _mongoService.getFarmStaff(_report.farmId);
    if (!mounted) return;
    setState(() {
      _references = refs;
      for (final s in staff.where((s) => s.isActive)) {
        if (!_staffStatuses.any((e) => e.staffId == s.id)) {
          _staffStatuses.add(StaffStatusEntry(staffId: s.id!, name: s.name, status: 'present'));
        }
      }
      _loadingRefs = false;
    });
  }

  Future<void> _saveStepAndAdvance() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await _mongoService.patchDailyReport(
      _report.id,
      consumptionByRoom: _step == 1 ? _consumption : null,
      mortalityByRoom: _step == 1 ? _mortality : null,
      clinicMortality: _step == 1 ? _clinicMortality : null,
      production: _step == 2 ? _production : null,
      waterLiters: _step == 2 ? _waterLiters : null,
      treatments: _step == 3 ? _treatments : null,
      staffStatuses: _step == 3 ? _staffStatuses : null,
      observation: _step == 3 ? _observation : null,
    );
    if (!mounted) return;
    if (result.error != null) {
      setState(() {
        _saving = false;
        _error = result.error;
      });
      return;
    }
    setState(() {
      _saving = false;
      _report = result.report!;
    });
    if (_step < 3) {
      setState(() => _step++);
    } else if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DailyReportSummaryScreen(user: widget.user, report: _report, readOnly: false),
        ),
      );
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: AppBar(
        backgroundColor: DailyReportColors.green900,
        foregroundColor: Colors.white,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
        title: Text(_stepTitles[_step]),
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: (_step + 1) / 4,
            backgroundColor: Colors.grey.shade200,
            color: DailyReportColors.yellow500,
            minHeight: 3,
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade50,
              padding: const EdgeInsets.all(10),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ),
          Expanded(
            child: _loadingRefs
                ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildStep(),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : _back,
                  child: const Text('Retour'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _saving ? null : _saveStepAndAdvance,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DailyReportColors.green700,
                    foregroundColor: Colors.white,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_step < 3 ? 'Suivant' : 'Voir le récapitulatif'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _buildIdentificationStep();
      case 1:
        return _buildAlimentMortaliteStep();
      case 2:
        return _buildProductionEauStep();
      default:
        return _buildTraitementsPersonnelStep();
    }
  }

  // ---- Étape 1 : identification & effectifs (lecture seule) ----
  Widget _buildIdentificationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Identification'),
        _card([
          _readonlyRow('Bâtiment', _report.farmName),
          _readonlyRow('Lot', _report.lotNumber ?? '—'),
          _readonlyRow(
            'Date · Âge',
            '${DateFormat('dd/MM/yyyy').format(DateTime.parse(_report.date))}'
                '${_report.ageDays != null ? " · ${_report.ageDays} j" : ""}',
          ),
        ]),
        const SizedBox(height: 16),
        _sectionTitle('Effectif début de journée'),
        _card([
          for (final r in _report.startCounts)
            _readonlyRow(r.roomName, 'F: ${r.femaleCount}   M: ${r.maleCount}'),
          _readonlyRow(
            'Clinique',
            'F: ${_report.clinicStart.femaleCount}   M: ${_report.clinicStart.maleCount}',
          ),
        ]),
      ],
    );
  }

  // ---- Étape 2 : aliment & mortalité ----
  Widget _buildAlimentMortaliteStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Aliment (kg)'),
        _card([
          _readonlyRow('Reçu aujourd\'hui', '${_report.aliment.receivedTotalKg} kg'),
          if (_report.aliment.receivedDetail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _report.aliment.receivedDetail
                    .map((d) => Chip(label: Text('${d.formulaName} · ${d.quantity} kg')))
                    .toList(),
              ),
            ),
          const Divider(),
          for (var i = 0; i < _consumption.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _numberField(
                label: 'Consommé — ${_consumption[i].roomName}',
                value: _consumption[i].quantityKg,
                onChanged: (v) => setState(() => _consumption[i] = _consumption[i].copyWith(quantityKg: v)),
              ),
            ),
          const Divider(),
          _readonlyRow('Stock avant', '${_report.aliment.stockBeforeKg} kg'),
        ]),
        const SizedBox(height: 16),
        _sectionTitle('Mortalité'),
        _card([
          for (var i = 0; i < _mortality.length; i++) ...[
            Text(_mortality[i].roomName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Row(
              children: [
                Expanded(
                  child: _stepperField(
                    label: 'Femelles',
                    value: _mortality[i].femaleCount,
                    onChanged: (v) => setState(() => _mortality[i] = _mortality[i].copyWith(femaleCount: v)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _stepperField(
                    label: 'Mâles',
                    value: _mortality[i].maleCount,
                    onChanged: (v) => setState(() => _mortality[i] = _mortality[i].copyWith(maleCount: v)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Text('Clinique', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          Row(
            children: [
              Expanded(
                child: _stepperField(
                  label: 'Femelles',
                  value: _clinicMortality.femaleCount,
                  onChanged: (v) => setState(
                    () => _clinicMortality = SexCount(femaleCount: v, maleCount: _clinicMortality.maleCount),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _stepperField(
                  label: 'Mâles',
                  value: _clinicMortality.maleCount,
                  onChanged: (v) => setState(
                    () => _clinicMortality = SexCount(femaleCount: _clinicMortality.femaleCount, maleCount: v),
                  ),
                ),
              ),
            ],
          ),
          const Divider(),
          _readonlyRow(
            'Cumul · Taux femelles',
            '${_report.mortality.cumulativeFemale} · ${_report.mortality.rateFemalePercent ?? "—"}%',
          ),
          _readonlyRow(
            'Cumul · Taux mâles',
            '${_report.mortality.cumulativeMale} · ${_report.mortality.rateMalePercent ?? "—"}%',
          ),
        ]),
      ],
    );
  }

  // ---- Étape 3 : production & eau ----
  Widget _buildProductionEauStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _production.length; i++) ...[
          _sectionTitle('Production — ${_production[i].roomName}'),
          _card([
            Row(
              children: [
                Expanded(
                  child: _intField('OAC', _production[i].oac,
                      (v) => setState(() => _production[i] = _production[i].copyWith(oac: v))),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _intField('PO', _production[i].po,
                      (v) => setState(() => _production[i] = _production[i].copyWith(po: v))),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _intField('DJ', _production[i].dj,
                      (v) => setState(() => _production[i] = _production[i].copyWith(dj: v))),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _intField('CAS', _production[i].cas,
                      (v) => setState(() => _production[i] = _production[i].copyWith(cas: v))),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _intField('SAL', _production[i].sal,
                      (v) => setState(() => _production[i] = _production[i].copyWith(sal: v))),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _intField('Ramassés au sol', _production[i].sol,
                (v) => setState(() => _production[i] = _production[i].copyWith(sol: v))),
            const Divider(),
            _readonlyRow(
              'Total · TP · Écart',
              '${_report.production[i].po} · ${_report.production[i].tpPercent}% · '
                  '${_report.production[i].ecartPercent ?? "—"}',
            ),
            _readonlyRow(
              '%DE · %SOL · Cumul',
              '${_report.production[i].dePercent}% · ${_report.production[i].solPercent}% · '
                  '${_report.production[i].cumulativePo}',
            ),
          ]),
          const SizedBox(height: 16),
        ],
        _sectionTitle('Eau'),
        _card([
          _numberField(
            label: 'Litres consommés',
            value: _waterLiters,
            onChanged: (v) => setState(() => _waterLiters = v),
          ),
        ]),
      ],
    );
  }

  // ---- Étape 4 : traitements & personnel ----
  Widget _buildTraitementsPersonnelStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Traitements'),
        _card([
          for (var i = 0; i < _treatments.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_treatments[i].name),
              subtitle: Text(
                '${_treatments[i].dose ?? ""}'
                '${_treatments[i].date != null ? " · ${DateFormat('dd/MM/yyyy').format(_treatments[i].date!)}" : ""}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _treatments.removeAt(i)),
              ),
            ),
          TextButton.icon(
            onPressed: _addTreatmentDialog,
            icon: const Icon(Icons.add, color: DailyReportColors.green700),
            label: const Text('Ajouter un traitement', style: TextStyle(color: DailyReportColors.green700)),
          ),
        ]),
        const SizedBox(height: 16),
        _sectionTitle('Personnel en poste'),
        _card([
          if (_staffStatuses.isEmpty)
            Text('Aucun personnel affecté à cette ferme.', style: TextStyle(color: Colors.grey.shade600)),
          for (var i = 0; i < _staffStatuses.length; i++) ...[
            Text(_staffStatuses[i].name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: kStaffStatuses.map((s) {
                final selected = _staffStatuses[i].status == s;
                return ChoiceChip(
                  label: Text(kStaffStatusLabels[s]!),
                  selected: selected,
                  selectedColor: DailyReportColors.green600,
                  labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87, fontSize: 11.5),
                  onSelected: (_) => setState(() => _staffStatuses[i] = _staffStatuses[i].copyWith(status: s)),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
        ]),
        const SizedBox(height: 16),
        _sectionTitle('Observation'),
        _card([
          TextFormField(
            initialValue: _observation,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Remarques du jour (facultatif)',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => _observation = v,
          ),
        ]),
      ],
    );
  }

  void _addTreatmentDialog() {
    TreatmentReference? selectedRef = _references.isNotEmpty ? _references.first : null;
    final doseController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Ajouter un traitement'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_references.isEmpty)
                const Text("Aucun vaccin/médicament dans le référentiel admin.")
              else
                DropdownButtonFormField<TreatmentReference>(
                  value: selectedRef,
                  items: _references
                      .map((r) => DropdownMenuItem(
                            value: r,
                            child: Text('${r.type == "vaccin" ? "💉" : "💊"} ${r.name}'),
                          ))
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedRef = v),
                  decoration: const InputDecoration(labelText: 'Vaccin / médicament'),
                ),
              TextField(
                controller: doseController,
                decoration: const InputDecoration(labelText: 'Dose'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Date : ${DateFormat('dd/MM/yyyy').format(selectedDate)}'),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                      );
                      if (picked != null) setDialogState(() => selectedDate = picked);
                    },
                    child: const Text('Changer'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: selectedRef == null
                  ? null
                  : () {
                      setState(() {
                        _treatments.add(TreatmentEntry(
                          referenceId: selectedRef!.id!,
                          type: selectedRef!.type,
                          name: selectedRef!.name,
                          dose: doseController.text.trim().isEmpty ? null : doseController.text.trim(),
                          date: selectedDate,
                        ));
                      });
                      Navigator.pop(context);
                    },
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.grey.shade600, letterSpacing: 0.5),
        ),
      );

  Widget _card(List<Widget> children) => Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      );

  Widget _readonlyRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5))),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      );

  Widget _numberField({required String label, double? value, required ValueChanged<double?> onChanged}) {
    return TextFormField(
      initialValue: value?.toString() ?? '',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
      onChanged: (v) => onChanged(double.tryParse(v.replaceAll(',', '.'))),
    );
  }

  Widget _intField(String label, int value, ValueChanged<int> onChanged) {
    return TextFormField(
      initialValue: value.toString(),
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
      onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
    );
  }

  Widget _stepperField({required String label, required int value, required ValueChanged<int> onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: value > 0 ? () => onChanged(value - 1) : null,
              ),
              SizedBox(width: 24, child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.add_circle_outline, size: 20),
                onPressed: () => onChanged(value + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
