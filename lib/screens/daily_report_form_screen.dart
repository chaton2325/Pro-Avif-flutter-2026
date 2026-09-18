import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/farm_daily_report.dart';
import '../models/formula.dart';
import '../models/lot_headcount.dart';
import '../models/treatment_reference.dart';
import '../models/user.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
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
  List<Formula> _formulas = [];
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
    final formulas = List.of(await _mongoService.getAllFormulas())
      ..retainWhere((f) => f.isActive)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!mounted) return;
    setState(() {
      _references = refs;
      _formulas = formulas;
      for (final s in staff.where((s) => s.isActive)) {
        if (!_staffStatuses.any((e) => e.staffId == s.id)) {
          _staffStatuses.add(StaffStatusEntry(staffId: s.id!, name: s.name, status: 'present'));
        }
      }
      _loadingRefs = false;
    });
  }

  Future<void> _saveStepAndAdvance() async {
    if (_step == 1 && _consumption.any((c) => c.quantityKg > 0 && c.formulaId == null)) {
      setState(() => _error = "Choisissez l'aliment consommé pour chaque salle ayant une quantité saisie.");
      return;
    }
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
      appBar: dailyReportAppBar(
        _stepTitles[_step],
        subtitle: 'Étape ${_step + 1} / 4',
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: List.generate(4, (i) {
                final active = i <= _step;
                return Expanded(
                  child: Container(
                    height: 5,
                    margin: EdgeInsets.only(right: i < 3 ? 5 : 0),
                    decoration: BoxDecoration(
                      color: active ? DailyReportColors.yellow500 : Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
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
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: _saving ? null : _back,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DailyReportColors.green700,
                      side: const BorderSide(color: DailyReportColors.green600, width: 1.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Retour', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
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
                      onTap: _saving ? null : _saveStepAndAdvance,
                      child: Center(
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(
                                _step < 3 ? 'Suivant' : 'Voir le récapitulatif',
                                style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
                              ),
                      ),
                    ),
                  ),
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
          for (var i = 0; i < _consumption.length; i++) _consumptionRow(i),
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

  Widget _sectionTitle(String title) => DailyReportSectionLabel(title);

  Widget _card(List<Widget> children) => DailyReportCard(children: children);

  Widget _readonlyRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5))),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: DailyReportColors.green900)),
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

  /// Salle + aliment consommé (référentiel Usine Aliment) + quantité — l'aliment est
  /// nécessaire pour que le stock de la ferme (farm_feed_stocks) puisse être débité du bon
  /// aliment à la validation du rapport (routers/daily_reports.py).
  Widget _consumptionRow(int i) {
    final entry = _consumption[i];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.roomName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  initialValue: entry.formulaId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Aliment', isDense: true, border: OutlineInputBorder()),
                  hint: const Text('Choisir'),
                  items: _formulas
                      .map((f) => DropdownMenuItem(value: f.id, child: Text(f.name, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (formulaId) => setState(() {
                    final formula = _formulas.firstWhere((f) => f.id == formulaId);
                    _consumption[i] = entry.copyWith(formulaId: formula.id, formulaName: formula.name);
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _numberField(
                  label: 'Kg',
                  value: entry.quantityKg,
                  onChanged: (v) => setState(() => _consumption[i] = _consumption[i].copyWith(quantityKg: v)),
                ),
              ),
            ],
          ),
        ],
      ),
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
    final active = value > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? DailyReportColors.yellow100 : DailyReportColors.surface,
        border: Border.all(color: active ? DailyReportColors.yellow500 : Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.remove_circle, size: 22, color: value > 0 ? DailyReportColors.green700 : Colors.grey.shade300),
                onPressed: value > 0 ? () => onChanged(value - 1) : null,
              ),
              SizedBox(
                width: 26,
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w800, color: active ? DailyReportColors.yellow600 : DailyReportColors.green900),
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.add_circle, size: 22, color: DailyReportColors.green700),
                onPressed: () => onChanged(value + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
