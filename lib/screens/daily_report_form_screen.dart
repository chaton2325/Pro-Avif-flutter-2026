import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/farm_daily_report.dart';
import '../models/farm_feed_stock.dart';
import '../models/formula.dart';
import '../models/lot_headcount.dart';
import '../models/treatment_reference.dart';
import '../models/user.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
import 'daily_report_summary_screen.dart';

const List<String> kStaffStatuses = [
  'present',
  'repos',
  'absent',
  'malade',
  'permission',
  'affecte',
  'sanctionne',
];
const Map<String, String> kStaffStatusLabels = {
  'present': 'Présent',
  'repos': 'Repos',
  'absent': 'Absent',
  'malade': 'Malade',
  'permission': 'Permission',
  'affecte': 'Affecté',
  'sanctionne': 'Sanctionné',
};

/// Formulaire du rapport en 4 étapes (maquette écrans 03-06) : identification & effectifs
/// (lecture seule), aliment & mortalité, production & eau, traitements & personnel. Chaque
/// "Suivant" sauvegarde l'étape (PATCH) et recharge les champs AUTO recalculés côté serveur.
class DailyReportFormScreen extends StatefulWidget {
  final User user;
  final FarmDailyReport report;

  const DailyReportFormScreen({
    super.key,
    required this.user,
    required this.report,
  });

  @override
  State<DailyReportFormScreen> createState() => _DailyReportFormScreenState();
}

class _DailyReportFormScreenState extends State<DailyReportFormScreen> {
  final MongoService _mongoService = MongoService();
  late FarmDailyReport _report;
  int _step = 0;
  final PageController _pageController = PageController();
  bool _saving = false;
  String? _error;

  late List<RoomConsumptionEntry> _consumption;
  late List<RoomHeadcount> _mortality;
  late SexCount _clinicMortality;
  late List<RoomProduction> _production;
  double? _waterLiters;
  late List<TreatmentEntry> _treatments;
  // Question posée avant de proposer la saisie : tant que la réponse est "Non" (ou pas encore
  // répondue), on ne montre ni la liste ni le bouton "Ajouter" pour ce type — évite de mélanger
  // vaccins et médicaments dans un même sélecteur et de laisser deviner s'il y a eu un service.
  late bool _medicamentDone;
  late bool _vaccinDone;
  late List<StaffStatusEntry> _staffStatuses;
  String? _observation;

  List<TreatmentReference> _references = [];
  List<Formula> _formulas = [];
  // Aliments que CETTE ferme a réellement en stock (farm_feed_stocks) — le référentiel
  // "formulas" est global à toutes les usines, et deux usines peuvent définir un aliment du
  // même nom (ex. "RL1") avec un formulaId différent : sans ce filtre, le menu déroulant
  // affiche chaque nom en double, sans distinction possible pour qui saisit.
  Set<String> _stockFormulaIds = {};
  bool _loadingRefs = true;

  List<Formula> get _consumableFormulas {
    if (_stockFormulaIds.isEmpty) return _formulas;
    final alreadySelected = _consumption
        .map((c) => c.formulaId)
        .whereType<String>()
        .toSet();
    return _formulas
        .where(
          (f) =>
              _stockFormulaIds.contains(f.id) || alreadySelected.contains(f.id),
        )
        .toList();
  }

  /// Même palette que le récapitulatif (DailyReportColors.alimentPalette) : un aliment garde
  /// la même couleur de la saisie jusqu'à la relecture par le validateur — assignée dans
  /// l'ordre de première apparition, jamais deux aliments avec la même tant qu'il reste une
  /// couleur libre.
  Map<String, Color> get _alimentColors {
    final map = <String, Color>{};
    for (final c in _consumption) {
      if (c.formulaId == null) continue;
      map.putIfAbsent(
        c.formulaId!,
        () =>
            DailyReportColors.alimentPalette[map.length %
                DailyReportColors.alimentPalette.length],
      );
    }
    return map;
  }

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
    // Une salle peut consommer plusieurs aliments le même jour (transition de formule, mix,
    // etc.) — donc pas une seule entrée par salle : toutes celles déjà saisies, ou une seule
    // vide par défaut pour une salle qui n'en a encore aucune.
    _consumption = [
      for (final r in _report.startCounts)
        ..._report.aliment.consumptionByRoom
                .where((c) => c.roomName == r.roomName)
                .isEmpty
            ? [RoomConsumptionEntry(roomName: r.roomName)]
            : _report.aliment.consumptionByRoom.where(
                (c) => c.roomName == r.roomName,
              ),
    ];
    _mortality = _report.startCounts
        .map(
          (r) => _report.mortality.byRoom.firstWhere(
            (m) => m.roomName == r.roomName,
            orElse: () => RoomHeadcount(roomName: r.roomName),
          ),
        )
        .toList();
    _clinicMortality = _report.mortality.clinic;
    _production = _report.startCounts
        .map(
          (r) => _report.production.firstWhere(
            (p) => p.roomName == r.roomName,
            orElse: () => RoomProduction(roomName: r.roomName),
          ),
        )
        .toList();
    _waterLiters = _report.waterLiters;
    _treatments = List.of(_report.treatments);
    // Un rapport rouvert qui a déjà des traitements enregistrés doit rouvrir la question sur
    // "Oui" et montrer ce qui existe déjà, pas repartir de "Non" comme si de rien n'était.
    _medicamentDone = _treatments.any((t) => t.type == 'medicament');
    _vaccinDone = _treatments.any((t) => t.type == 'vaccin');
    _staffStatuses = List.of(_report.staffStatuses);
    _observation = _report.observation;
    _loadReferentials();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadReferentials() async {
    final refs = await _mongoService.getTreatmentReferences();
    final staff = await _mongoService.getFarmStaff(_report.farmId);
    final formulas = List.of(await _mongoService.getAllFormulas())
      ..retainWhere((f) => f.isActive)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final feedStock = await _mongoService.getFarmFeedStock(_report.farmName);
    if (!mounted) return;
    setState(() {
      _references = refs;
      _formulas = formulas;
      _stockFormulaIds = {
        for (final q in feedStock?.quantities ?? <FeedStartingQuantity>[])
          if (q.quantityKg > 0) q.formulaId,
      };
      for (final s in staff.where((s) => s.isActive)) {
        if (!_staffStatuses.any((e) => e.staffId == s.id)) {
          _staffStatuses.add(
            StaffStatusEntry(staffId: s.id!, name: s.name, status: 'present'),
          );
        }
      }
      _loadingRefs = false;
    });
  }

  /// Sauvegarde les champs d'UNE étape précise (PATCH ciblé) et recharge les champs AUTO
  /// recalculés côté serveur — appelé en arrière-plan à chaque fois qu'on quitte une étape en
  /// faisant glisser l'écran (voir _onPageChanged), plus une dernière fois avant d'ouvrir le
  /// récapitulatif. Retourne false sans rien envoyer si l'étape n'est pas valide : l'erreur
  /// reste affichée, mais ne bloque jamais le glissement déjà en cours (voir _onPageChanged).
  Future<bool> _saveStep(int step) async {
    if (step == 1 &&
        _consumption.any((c) => c.quantityKg > 0 && c.formulaId == null)) {
      setState(
        () => _error =
            "Choisissez l'aliment consommé pour chaque salle ayant une quantité saisie.",
      );
      return false;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await _mongoService.patchDailyReport(
      _report.id,
      consumptionByRoom: step == 1 ? _consumption : null,
      mortalityByRoom: step == 1 ? _mortality : null,
      clinicMortality: step == 1 ? _clinicMortality : null,
      production: step == 2 ? _production : null,
      waterLiters: step == 2 ? _waterLiters : null,
      treatments: step == 3 ? _treatments : null,
      staffStatuses: step == 3 ? _staffStatuses : null,
      observation: step == 3 ? _observation : null,
    );
    if (!mounted) return false;
    if (result.error != null) {
      setState(() {
        _saving = false;
        _error = result.error;
      });
      return false;
    }
    setState(() {
      _saving = false;
      _report = result.report!;
    });
    return true;
  }

  /// Glissement horizontal entre étapes (remplace les boutons Suivant/Retour) : l'étape qu'on
  /// vient de quitter est sauvegardée en arrière-plan, sans jamais bloquer ni annuler le
  /// glissement déjà effectué par l'utilisateur.
  void _onPageChanged(int newIndex) {
    final leftStep = _step;
    setState(() => _step = newIndex);
    _saveStep(leftStep);
  }

  Future<void> _finishAndReview() async {
    final ok = await _saveStep(3);
    if (!ok || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DailyReportSummaryScreen(
          user: widget.user,
          report: _report,
          readOnly: false,
        ),
      ),
    );
  }

  void _back() {
    if (_step > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    } else {
      Navigator.pop(context);
    }
  }

  void _goToStep(int step) {
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  /// Un rapport "à corriger" avec des endroits précis flagués par le validateur ne montre que
  /// ces endroits-là, sur une seule page (_buildCorrectionScaffold) — jamais l'assistant en 4
  /// étapes complet, pour ne pas laisser deviner ce qui a vraiment besoin d'être revu.
  bool get _isTargetedCorrection => widget.report.status == 'a_corriger' && widget.report.rejectionFlags.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (_isTargetedCorrection) return _buildCorrectionScaffold();
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar(
        _stepTitles[_step],
        subtitle: 'Étape ${_step + 1} / 4',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _back,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: List.generate(4, (i) {
                final active = i <= _step;
                // Cliquable : sans bouton Retour/Suivant, c'est le seul moyen de sauter
                // directement à une étape sans glisser plusieurs fois de suite.
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _goToStep(i),
                    child: Container(
                      height: 5,
                      margin: EdgeInsets.only(right: i < 3 ? 5 : 0),
                      decoration: BoxDecoration(
                        color: active
                            ? DailyReportColors.yellow500
                            : Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(3),
                      ),
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
              child: Text(
                _error!,
                style: TextStyle(color: Colors.red.shade700),
              ),
            ),
          Expanded(
            child: _loadingRefs
                ? const Center(
                    child: CircularProgressIndicator(
                      color: DailyReportColors.green700,
                    ),
                  )
                // Glissement horizontal entre les 4 étapes (remplace Suivant/Retour) — chaque
                // étape garde son propre défilement vertical indépendant (voir _onPageChanged
                // pour la sauvegarde en arrière-plan à chaque changement de page).
                : PageView(
                    controller: _pageController,
                    onPageChanged: _onPageChanged,
                    children: [
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: _buildIdentificationStep(),
                      ),
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: _buildAlimentMortaliteStep(),
                      ),
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: _buildProductionEauStep(),
                      ),
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: _buildTraitementsPersonnelStep(),
                      ),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: _step < 3
              // Rappel discret plutôt qu'un bouton : la navigation se fait en glissant l'écran.
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.swipe_rounded, size: 16, color: Colors.grey.shade400),
                    const SizedBox(width: 6),
                    Text(
                      'Glissez pour continuer',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                )
              : SizedBox(
                  height: 50,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [
                          DailyReportColors.green700,
                          DailyReportColors.green600,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: DailyReportColors.green700.withValues(
                            alpha: 0.32,
                          ),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _saving ? null : _finishAndReview,
                        child: Center(
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Voir le récapitulatif',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  // ---- Vue de correction ciblée : seuls les endroits flagués par le validateur, une seule
  // page, avec un accès au récapitulatif global pour le contexte (voir _isTargetedCorrection).
  Future<void> _saveCorrectionAndReview() async {
    if (_consumption.any((c) => c.quantityKg > 0 && c.formulaId == null)) {
      setState(() => _error = "Choisissez l'aliment consommé pour chaque salle ayant une quantité saisie.");
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await _mongoService.patchDailyReport(
      _report.id,
      consumptionByRoom: _consumption,
      mortalityByRoom: _mortality,
      clinicMortality: _clinicMortality,
      production: _production,
      waterLiters: _waterLiters,
      treatments: _treatments,
      staffStatuses: _staffStatuses,
      observation: _observation,
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
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DailyReportSummaryScreen(user: widget.user, report: _report, readOnly: false),
      ),
    );
  }

  Widget _buildCorrectionScaffold() {
    final flaggedRooms = <String, Set<String>>{};
    for (final f in _report.rejectionFlags) {
      if (f.roomName != null) flaggedRooms.putIfAbsent(f.roomName!, () => {}).add(f.field);
    }
    final globalFlags = _report.rejectionFlags.where((f) => f.roomName == null).map((f) => f.field).toSet();

    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar(
        'Corrections demandées',
        subtitle: _report.farmName,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_report.rejectionReason != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(color: DailyReportColors.yellow100, borderRadius: BorderRadius.circular(12)),
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(color: Colors.black87, fontSize: 13),
                                children: [
                                  const TextSpan(text: 'Motif du validateur : ', style: TextStyle(fontWeight: FontWeight.w800)),
                                  TextSpan(text: '« ${_report.rejectionReason} »'),
                                ],
                              ),
                            ),
                          ),
                        for (final entry in flaggedRooms.entries) _roomCorrectionCard(entry.key, entry.value),
                        if (globalFlags.contains('water')) ...[_waterSection(), const SizedBox(height: 16)],
                        if (globalFlags.contains('treatments')) ...[_treatmentsSection(), const SizedBox(height: 16)],
                        if (globalFlags.contains('staff')) ...[_personnelSection(), const SizedBox(height: 16)],
                        if (globalFlags.contains('observation')) _observationSection(),
                      ],
                    ),
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
                    onPressed: _saving
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DailyReportSummaryScreen(user: widget.user, report: _report, readOnly: true),
                              ),
                            ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DailyReportColors.green700,
                      side: const BorderSide(color: DailyReportColors.green600, width: 1.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Récapitulatif global', style: TextStyle(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
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
                      onTap: _saving ? null : _saveCorrectionAndReview,
                      child: Center(
                        child: _saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
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

  Widget _roomCorrectionCard(String roomName, Set<String> fields) {
    final mortIndex = _mortality.indexWhere((m) => m.roomName == roomName);
    final prodIndex = _production.indexWhere((p) => p.roomName == roomName);
    final hasProductionFlag = fields.any((f) => ['oac', 'po', 'dj', 'cas', 'sal'].contains(f));
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(roomName),
          _card([
            if (fields.contains('mortality') && mortIndex != -1) ...[
              const Text('Mortalité', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _stepperField(
                      label: 'Femelles',
                      value: _mortality[mortIndex].femaleCount,
                      onChanged: (v) => setState(() => _mortality[mortIndex] = _mortality[mortIndex].copyWith(femaleCount: v)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _stepperField(
                      label: 'Mâles',
                      value: _mortality[mortIndex].maleCount,
                      onChanged: (v) => setState(() => _mortality[mortIndex] = _mortality[mortIndex].copyWith(maleCount: v)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (fields.contains('consumption')) ...[
              const Text('Consommation', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 6),
              _roomConsumptionGroup(roomName),
            ],
            if (prodIndex != -1 && hasProductionFlag) ...[
              const Text('Production', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (fields.contains('oac'))
                    SizedBox(
                      width: 90,
                      child: _intField('OAC', _production[prodIndex].oac, (v) => setState(() => _production[prodIndex] = _production[prodIndex].copyWith(oac: v))),
                    ),
                  if (fields.contains('po'))
                    SizedBox(
                      width: 90,
                      child: _intField('PO', _production[prodIndex].po, (v) => setState(() => _production[prodIndex] = _production[prodIndex].copyWith(po: v))),
                    ),
                  if (fields.contains('dj'))
                    SizedBox(
                      width: 90,
                      child: _intField('DJ', _production[prodIndex].dj, (v) => setState(() => _production[prodIndex] = _production[prodIndex].copyWith(dj: v))),
                    ),
                  if (fields.contains('cas'))
                    SizedBox(
                      width: 90,
                      child: _intField('CAS', _production[prodIndex].cas, (v) => setState(() => _production[prodIndex] = _production[prodIndex].copyWith(cas: v))),
                    ),
                  if (fields.contains('sal'))
                    SizedBox(
                      width: 90,
                      child: _intField('SAL', _production[prodIndex].sal, (v) => setState(() => _production[prodIndex] = _production[prodIndex].copyWith(sal: v))),
                    ),
                ],
              ),
            ],
          ]),
        ],
      ),
    );
  }

  Widget _waterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          _readonlyRow(
            'Reçu aujourd\'hui',
            '${_report.aliment.receivedTotalKg} kg',
          ),
          if (_report.aliment.receivedDetail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _report.aliment.receivedTotalsByFormula.entries
                    .map(
                      (e) => Chip(
                        label: Text('${e.key} · ${e.value} kg'),
                      ),
                    )
                    .toList(),
              ),
            ),
          const Divider(),
          for (final r in _report.startCounts)
            _roomConsumptionGroup(r.roomName),
          _readonlyRow('Stock avant', '${_report.aliment.stockBeforeKg} kg'),
        ]),
        const SizedBox(height: 16),
        _sectionTitle('Mortalité'),
        _card([
          for (var i = 0; i < _mortality.length; i++) ...[
            Text(
              _mortality[i].roomName,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            Row(
              children: [
                Expanded(
                  child: _stepperField(
                    label: 'Femelles',
                    value: _mortality[i].femaleCount,
                    onChanged: (v) => setState(
                      () => _mortality[i] = _mortality[i].copyWith(
                        femaleCount: v,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _stepperField(
                    label: 'Mâles',
                    value: _mortality[i].maleCount,
                    onChanged: (v) => setState(
                      () =>
                          _mortality[i] = _mortality[i].copyWith(maleCount: v),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Text(
            'Clinique',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          Row(
            children: [
              Expanded(
                child: _stepperField(
                  label: 'Femelles',
                  value: _clinicMortality.femaleCount,
                  onChanged: (v) => setState(
                    () => _clinicMortality = SexCount(
                      femaleCount: v,
                      maleCount: _clinicMortality.maleCount,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _stepperField(
                  label: 'Mâles',
                  value: _clinicMortality.maleCount,
                  onChanged: (v) => setState(
                    () => _clinicMortality = SexCount(
                      femaleCount: _clinicMortality.femaleCount,
                      maleCount: v,
                    ),
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
                  child: _intField(
                    'OAC',
                    _production[i].oac,
                    (v) => setState(
                      () => _production[i] = _production[i].copyWith(oac: v),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _intField(
                    'PO',
                    _production[i].po,
                    (v) => setState(
                      () => _production[i] = _production[i].copyWith(po: v),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _intField(
                    'DJ',
                    _production[i].dj,
                    (v) => setState(
                      () => _production[i] = _production[i].copyWith(dj: v),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _intField(
                    'CAS',
                    _production[i].cas,
                    (v) => setState(
                      () => _production[i] = _production[i].copyWith(cas: v),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _intField(
                    'SAL',
                    _production[i].sal,
                    (v) => setState(
                      () => _production[i] = _production[i].copyWith(sal: v),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(),
            _readonlyRow(
              'Total · TP · Écart',
              '${_report.production[i].po} · ${_report.production[i].tpPercent}% · '
                  '${_report.production[i].ecartPercent ?? "—"}',
            ),
            _readonlyRow(
              '%DE · Cumul PO',
              '${_report.production[i].dePercent}% · ${_report.production[i].cumulativePo}',
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
        _treatmentsSection(),
        const SizedBox(height: 16),
        _personnelSection(),
        const SizedBox(height: 16),
        _observationSection(),
      ],
    );
  }

  /// Extraites de _buildTraitementsPersonnelStep pour être réutilisables telles quelles dans
  /// la vue de correction ciblée (un rapport "à corriger" ne montre que les sections flaguées
  /// par le validateur, voir _buildCorrectionView).
  Widget _treatmentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Traitements'),
        _card([
          _treatmentYesNoRow(
            'Un service médicament a été fait ?',
            _medicamentDone,
            (v) => setState(() {
              _medicamentDone = v;
              if (!v) _treatments.removeWhere((t) => t.type == 'medicament');
            }),
          ),
          if (_medicamentDone) ...[
            const SizedBox(height: 8),
            for (var i = 0; i < _treatments.length; i++)
              if (_treatments[i].type == 'medicament') _treatmentTile(i),
            TextButton.icon(
              onPressed: () => _addTreatmentDialog('medicament'),
              icon: const Icon(Icons.add, color: DailyReportColors.green700),
              label: const Text('Ajouter un médicament', style: TextStyle(color: DailyReportColors.green700)),
            ),
          ],
          const Divider(height: 24),
          _treatmentYesNoRow(
            'Un vaccin a été fait ?',
            _vaccinDone,
            (v) => setState(() {
              _vaccinDone = v;
              if (!v) _treatments.removeWhere((t) => t.type == 'vaccin');
            }),
          ),
          if (_vaccinDone) ...[
            const SizedBox(height: 8),
            for (var i = 0; i < _treatments.length; i++)
              if (_treatments[i].type == 'vaccin') _treatmentTile(i),
            TextButton.icon(
              onPressed: () => _addTreatmentDialog('vaccin'),
              icon: const Icon(Icons.add, color: DailyReportColors.green700),
              label: const Text('Ajouter un vaccin', style: TextStyle(color: DailyReportColors.green700)),
            ),
          ],
        ]),
      ],
    );
  }

  Widget _personnelSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Personnel en poste'),
        _card([
          if (_staffStatuses.isEmpty)
            Text(
              'Aucun personnel affecté à cette ferme.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          for (var i = 0; i < _staffStatuses.length; i++) ...[
            Text(
              _staffStatuses[i].name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: kStaffStatuses.map((s) {
                final selected = _staffStatuses[i].status == s;
                return ChoiceChip(
                  label: Text(kStaffStatusLabels[s]!),
                  selected: selected,
                  selectedColor: DailyReportColors.green600,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : Colors.black87,
                    fontSize: 11.5,
                  ),
                  onSelected: (_) => setState(
                    () => _staffStatuses[i] = _staffStatuses[i].copyWith(
                      status: s,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
        ]),
      ],
    );
  }

  Widget _observationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

  Widget _treatmentYesNoRow(String question, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(child: Text(question, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('Oui'),
          selected: value,
          selectedColor: DailyReportColors.green600,
          labelStyle: TextStyle(color: value ? Colors.white : Colors.black87, fontSize: 12, fontWeight: FontWeight.w700),
          onSelected: (_) => onChanged(true),
        ),
        const SizedBox(width: 6),
        ChoiceChip(
          label: const Text('Non'),
          selected: !value,
          selectedColor: Colors.grey.shade500,
          labelStyle: TextStyle(color: !value ? Colors.white : Colors.black87, fontSize: 12, fontWeight: FontWeight.w700),
          onSelected: (_) => onChanged(false),
        ),
      ],
    );
  }

  Widget _treatmentTile(int i) {
    final t = _treatments[i];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(t.name),
      subtitle: Text(
        '${t.dose ?? ""}${t.date != null ? " · ${DateFormat('dd/MM/yyyy').format(t.date!)}" : ""}',
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 18),
        onPressed: () => setState(() => _treatments.removeAt(i)),
      ),
    );
  }

  void _addTreatmentDialog(String type) {
    final typeRefs = _references.where((r) => r.type == type).toList();
    TreatmentReference? selectedRef = typeRefs.isNotEmpty ? typeRefs.first : null;
    final doseController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(type == 'vaccin' ? 'Ajouter un vaccin' : 'Ajouter un médicament'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (typeRefs.isEmpty)
                Text(type == 'vaccin'
                    ? "Aucun vaccin dans le référentiel admin."
                    : "Aucun médicament dans le référentiel admin.")
              else
                DropdownButtonFormField<TreatmentReference>(
                  value: selectedRef,
                  items: typeRefs
                      .map(
                        (r) => DropdownMenuItem(
                          value: r,
                          child: Text(r.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedRef = v),
                  decoration: InputDecoration(
                    labelText: type == 'vaccin' ? 'Vaccin' : 'Médicament',
                  ),
                ),
              TextField(
                controller: doseController,
                decoration: const InputDecoration(labelText: 'Dose'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Date : ${DateFormat('dd/MM/yyyy').format(selectedDate)}',
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 365),
                        ),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                      );
                      if (picked != null)
                        setDialogState(() => selectedDate = picked);
                    },
                    child: const Text('Changer'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: selectedRef == null
                  ? null
                  : () {
                      setState(() {
                        _treatments.add(
                          TreatmentEntry(
                            referenceId: selectedRef!.id!,
                            type: selectedRef!.type,
                            name: selectedRef!.name,
                            dose: doseController.text.trim().isEmpty
                                ? null
                                : doseController.text.trim(),
                            date: selectedDate,
                          ),
                        );
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
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: DailyReportColors.green900,
          ),
        ),
      ],
    ),
  );

  Widget _numberField({
    required String label,
    double? value,
    required ValueChanged<double?> onChanged,
  }) {
    return TextFormField(
      initialValue: value?.toString() ?? '',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: (v) => onChanged(double.tryParse(v.replaceAll(',', '.'))),
    );
  }

  /// Une salle peut consommer plusieurs aliments le même jour (transition de formule, mix…) :
  /// une ligne par aliment, un bouton pour en ajouter une autre pour cette salle, un formulaire
  /// déjà choisi dans une autre ligne de la même salle n'est plus proposé (doublon inutile —
  /// il faut augmenter la quantité de la ligne existante à la place).
  Widget _roomConsumptionGroup(String roomName) {
    final indices = [
      for (var i = 0; i < _consumption.length; i++)
        if (_consumption[i].roomName == roomName) i,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            roomName,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 6),
          for (final i in indices)
            _consumptionEntryRow(i, showDelete: indices.length > 1),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: indices.length >= _consumableFormulas.length
                  ? null
                  : () => setState(
                      () => _consumption.add(
                        RoomConsumptionEntry(roomName: roomName),
                      ),
                    ),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              icon: const Icon(Icons.add_circle_outline, size: 16),
              label: const Text(
                'Ajouter un aliment',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
          const Divider(),
        ],
      ),
    );
  }

  /// Aliment consommé (référentiel Usine Aliment) + quantité — l'aliment est nécessaire pour
  /// que le stock de la ferme (farm_feed_stocks) puisse être débité du bon aliment à la
  /// validation du rapport (routers/daily_reports.py).
  Widget _consumptionEntryRow(int i, {required bool showDelete}) {
    final entry = _consumption[i];
    final usedElsewhere = _consumption
        .where((c) => c.roomName == entry.roomName && c != entry)
        .map((c) => c.formulaId)
        .toSet();
    final selectable = _consumableFormulas
        .where((f) => f.id == entry.formulaId || !usedElsewhere.contains(f.id))
        .toList();
    // Pas encore d'aliment choisi sur cette ligne : gris neutre plutôt qu'une couleur de la
    // palette, pour ne pas préempter une couleur qu'une autre ligne pourrait ensuite recevoir.
    final color = entry.formulaId != null
        ? _alimentColors[entry.formulaId!] ?? Colors.grey.shade400
        : Colors.grey.shade400;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: entry.formulaId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Aliment',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    hint: const Text('Choisir'),
                    items: selectable
                        .map(
                          (f) => DropdownMenuItem(
                            value: f.id,
                            child: Text(
                              f.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (formulaId) => setState(() {
                      final formula = _formulas.firstWhere(
                        (f) => f.id == formulaId,
                      );
                      _consumption[i] = entry.copyWith(
                        formulaId: formula.id,
                        formulaName: formula.name,
                      );
                    }),
                  ),
                ),
                if (showDelete)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Colors.grey,
                    ),
                    onPressed: () => setState(() => _consumption.removeAt(i)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _numberField(
                    label: 'Femelles (kg)',
                    value: entry.femaleQuantityKg ?? 0,
                    onChanged: (v) => setState(
                      () => _consumption[i] = entry.copyWith(
                        femaleQuantityKg: v ?? 0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _numberField(
                    label: 'Mâles (kg)',
                    value: entry.maleQuantityKg ?? 0,
                    onChanged: (v) => setState(
                      () => _consumption[i] = entry.copyWith(
                        maleQuantityKg: v ?? 0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _intField(String label, int value, ValueChanged<int> onChanged) {
    return TextFormField(
      initialValue: value.toString(),
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
    );
  }

  Widget _stepperField({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    final active = value > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? DailyReportColors.yellow100 : DailyReportColors.surface,
        border: Border.all(
          color: active ? DailyReportColors.yellow500 : Colors.grey.shade300,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  Icons.remove_circle,
                  size: 22,
                  color: value > 0
                      ? DailyReportColors.green700
                      : Colors.grey.shade300,
                ),
                onPressed: value > 0 ? () => onChanged(value - 1) : null,
              ),
              SizedBox(
                width: 26,
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: active
                        ? DailyReportColors.yellow600
                        : DailyReportColors.green900,
                  ),
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(
                  Icons.add_circle,
                  size: 22,
                  color: DailyReportColors.green700,
                ),
                onPressed: () => onChanged(value + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
