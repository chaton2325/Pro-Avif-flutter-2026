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
  // Bâtiment en production ? Sinon l'étape 3 n'affiche que l'eau (défaut : non).
  bool _isProduction = false;
  // Champs dont la valeur « 0 » a été confirmée volontairement (0 est une valeur, pas un oubli).
  // Conservé par rapport pour la session : on revient sur le rapport sans tout perdre.
  static final Map<String, Set<String>> _confirmedByReport = {};
  // Incrémenté par « Confirmer ces champs à 0 » pour que les champs texte réaffichent « 0 ».
  int _zeroEpoch = 0;
  // Résolu à la demande (pas un champ `late`) : un hot reload sur un écran déjà ouvert ne
  // rejoue pas initState et ferait planter un champ jamais initialisé.
  Set<String> get _confirmed =>
      _confirmedByReport.putIfAbsent(widget.report.id, () => <String>{});
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
    if (_medicamentDone) _confirmed.add('q:med');
    if (_vaccinDone) _confirmed.add('q:vac');
    if (widget.report.status != 'brouillon') {
      // Déjà envoyé au validateur : tout a été renseigné, rien à signaler en rouge.
      _confirmed.addAll(['q:med', 'q:vac']);
      for (final m in _mortality) {
        _confirmed.addAll(['m:${m.roomName}:f', 'm:${m.roomName}:m', 'c:${m.roomName}']);
      }
      _confirmed.addAll(['m:Clinique:f', 'm:Clinique:m']);
      for (final pr in _production) {
        for (final f in ['oac', 'po', 'dj', 'cas', 'sal']) {
          _confirmed.add('p:${pr.roomName}:$f');
        }
      }
    }
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
    final farm = await _mongoService.getFarmById(_report.farmId);
    if (!mounted) return;
    setState(() {
      _isProduction = farm?.isProduction ?? false;
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

  // ---- Champs non renseignés ----
  // Règle : un champ numérique est « renseigné » s'il est > 0 OU si l'utilisateur a confirmé 0
  // (tapé dessus, modifié, ou « Confirmer à 0 »). Un rapport déjà envoyé (à corriger) est
  // considéré entièrement renseigné.

  bool _zeroUnconfirmed(String key, int value) => value == 0 && !_confirmed.contains(key);

  bool _consumptionMissing(String roomName) =>
      !_confirmed.contains('c:$roomName') &&
      !_consumption.any((c) => c.roomName == roomName && c.quantityKg > 0);

  List<({int step, String label, String? key})> _missingFields() {
    final out = <({int step, String label, String? key})>[];
    for (final m in _mortality) {
      if (_zeroUnconfirmed('m:${m.roomName}:f', m.femaleCount)) {
        out.add((step: 1, label: '${m.roomName} · mortalité femelles', key: 'm:${m.roomName}:f'));
      }
      if (_zeroUnconfirmed('m:${m.roomName}:m', m.maleCount)) {
        out.add((step: 1, label: '${m.roomName} · mortalité mâles', key: 'm:${m.roomName}:m'));
      }
    }
    if (_zeroUnconfirmed('m:Clinique:f', _clinicMortality.femaleCount)) {
      out.add((step: 1, label: 'Clinique · mortalité femelles', key: 'm:Clinique:f'));
    }
    if (_zeroUnconfirmed('m:Clinique:m', _clinicMortality.maleCount)) {
      out.add((step: 1, label: 'Clinique · mortalité mâles', key: 'm:Clinique:m'));
    }
    for (final r in _report.startCounts) {
      if (_consumptionMissing(r.roomName)) {
        out.add((step: 1, label: '${r.roomName} · consommation d\'aliment', key: 'c:${r.roomName}'));
      }
    }
    if (_isProduction) {
      for (final p in _production) {
        final values = {'oac': p.oac, 'po': p.po, 'dj': p.dj, 'cas': p.cas, 'sal': p.sal};
        values.forEach((field, v) {
          final key = 'p:${p.roomName}:$field';
          if (_zeroUnconfirmed(key, v)) {
            out.add((step: 2, label: '${p.roomName} · ${field.toUpperCase()}', key: key));
          }
        });
      }
    }
    if (_waterLiters == null) {
      out.add((step: 2, label: 'Eau consommée', key: null));
    }
    if (!_confirmed.contains('q:med')) {
      out.add((step: 3, label: 'Service médicament : oui ou non ?', key: null));
    }
    if (!_confirmed.contains('q:vac')) {
      out.add((step: 3, label: 'Vaccin : oui ou non ?', key: null));
    }
    return out;
  }

  int _missingCount(int step) => _missingFields().where((m) => m.step == step).length;

  /// Bandeau en tête de chaque étape : combien de champs restent à renseigner (en rouge),
  /// ou une confirmation verte. Le bouton confirme « 0 » pour les quantités non saisies.
  Widget _stepBanner(int step) {
    final missing = _missingFields().where((m) => m.step == step).toList();
    if (missing.isEmpty) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: DailyReportColors.green100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_rounded, size: 18, color: DailyReportColors.green700),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Tout est renseigné sur cette étape',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: DailyReportColors.green900),
              ),
            ),
          ],
        ),
      );
    }
    final confirmable = missing.where((m) => m.key != null).toList();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 18, color: Colors.red.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${missing.length} champ${missing.length > 1 ? "s" : ""} à renseigner (en rouge)',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: Colors.red.shade800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '0 est une valeur : saisissez 0 (ou touchez le chiffre) si rien à déclarer.',
            style: TextStyle(fontSize: 11.5, color: Colors.red.shade700),
          ),
          if (confirmable.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: Colors.red.shade800,
                ),
                onPressed: () => setState(() {
                  for (final m in confirmable) {
                    _confirmed.add(m.key!);
                  }
                  _zeroEpoch++;
                }),
                child: const Text('Confirmer ces champs à 0'),
              ),
            ),
        ],
      ),
    );
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
      production: step == 2 && _isProduction ? _production : null,
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
    final missing = _missingFields();
    if (missing.isNotEmpty) {
      const stepNames = {1: 'Aliment & mortalité', 2: 'Production & eau', 3: 'Traitements'};
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.red.shade700),
              const SizedBox(width: 8),
              Expanded(child: Text('${missing.length} champ${missing.length > 1 ? "s" : ""} non renseigné${missing.length > 1 ? "s" : ""}')),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                const Text(
                  '0 est une valeur : un champ resté vide est considéré comme oublié.',
                  style: TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                for (final step in [1, 2, 3])
                  if (missing.any((m) => m.step == step)) ...[
                    Text(stepNames[step]!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                    for (final m in missing.where((m) => m.step == step))
                      Padding(
                        padding: const EdgeInsets.only(left: 8, top: 2),
                        child: Text('• ${m.label}', style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                      ),
                    const SizedBox(height: 8),
                  ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Compléter')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continuer quand même')),
          ],
        ),
      );
      if (go != true) {
        if (mounted) _goToStep(missing.first.step);
        return;
      }
    }
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
        (_step == 2 && !_isProduction) ? 'Eau' : _stepTitles[_step],
        // Entête : l'étape en cours + le total de champs encore à renseigner (tout le rapport).
        subtitle: 'Étape ${_step + 1} / 4'
            '${_missingFields().isEmpty ? " · tout est renseigné" : " · ${_missingFields().length} à renseigner"}',
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
                // Étape déjà passée avec des champs non renseignés : rouge ; complète : vert.
                final missingHere = i == 0 ? 0 : _missingCount(i);
                final barColor = i == 0
                    ? (active ? DailyReportColors.yellow500 : Colors.white.withValues(alpha: 0.25))
                    : missingHere == 0
                        ? const Color(0xFF7CE38B)
                        : (i < _step
                            ? Colors.red.shade400
                            : (active ? DailyReportColors.yellow500 : Colors.white.withValues(alpha: 0.25)));
                // Cliquable : sans bouton Retour/Suivant, c'est le seul moyen de sauter
                // directement à une étape sans glisser plusieurs fois de suite.
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _goToStep(i),
                    child: Container(
                      height: 5,
                      margin: EdgeInsets.only(right: i < 3 ? 5 : 0),
                      decoration: BoxDecoration(
                        color: barColor,
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [_stepBanner(1), _buildAlimentMortaliteStep()],
                        ),
                      ),
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [_stepBanner(2), _buildProductionEauStep()],
                        ),
                      ),
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [_stepBanner(3), _buildTraitementsPersonnelStep()],
                        ),
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
            missing: _waterLiters == null,
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
          const Divider(),
          _readonlyRow(
            'Total',
            'F: ${_report.startCounts.fold<int>(_report.clinicStart.femaleCount, (s, r) => s + r.femaleCount)}'
                '   M: ${_report.startCounts.fold<int>(_report.clinicStart.maleCount, (s, r) => s + r.maleCount)}',
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
                    fieldKey: 'm:${_mortality[i].roomName}:f',
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
                    fieldKey: 'm:${_mortality[i].roomName}:m',
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
                  fieldKey: 'm:Clinique:f',
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
                  fieldKey: 'm:Clinique:m',
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
        if (_isProduction)
        for (var i = 0; i < _production.length; i++) ...[
          _sectionTitle('Production — ${_production[i].roomName}'),
          _card([
            Row(
              children: [
                Expanded(
                  child: _intField(
                    'OAC',
                    _production[i].oac,
                    fieldKey: 'p:${_production[i].roomName}:oac',
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
                    fieldKey: 'p:${_production[i].roomName}:po',
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
                    fieldKey: 'p:${_production[i].roomName}:dj',
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
                    fieldKey: 'p:${_production[i].roomName}:cas',
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
                    fieldKey: 'p:${_production[i].roomName}:sal',
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
            missing: _waterLiters == null,
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
            answered: _confirmed.contains('q:med'),
            (v) => setState(() {
              _confirmed.add('q:med');
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
            answered: _confirmed.contains('q:vac'),
            (v) => setState(() {
              _confirmed.add('q:vac');
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

  Widget _treatmentYesNoRow(String question, bool value, ValueChanged<bool> onChanged, {bool answered = true}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            answered ? question : '$question  (à répondre)',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
              color: answered ? null : Colors.red.shade700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('Oui'),
          selected: answered && value,
          selectedColor: DailyReportColors.green600,
          labelStyle: TextStyle(color: answered && value ? Colors.white : Colors.black87, fontSize: 12, fontWeight: FontWeight.w700),
          onSelected: (_) => onChanged(true),
        ),
        const SizedBox(width: 6),
        ChoiceChip(
          label: const Text('Non'),
          selected: answered && !value,
          selectedColor: Colors.grey.shade500,
          labelStyle: TextStyle(color: answered && !value ? Colors.white : Colors.black87, fontSize: 12, fontWeight: FontWeight.w700),
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

  String _unitLabel(String? unit) {
    final u = (unit ?? '').trim();
    return u.isEmpty || u.toLowerCase() == 'doses' ? 'Quantité' : u;
  }

  /// Dose saisie + unité du référentiel (« 5 » + « g » -> « 5 g »). Une saisie qui contient
  /// déjà du texte (ex. « 2 sachets ») est conservée telle quelle.
  String? _doseWithUnit(String raw, String unit) {
    final text = raw.trim().replaceAll(',', '.');
    if (text.isEmpty) return null;
    final isNumeric = double.tryParse(text) != null;
    final showUnit = unit.trim().isNotEmpty && unit.trim().toLowerCase() != 'doses';
    return isNumeric && showUnit ? '$text ${unit.trim()}' : text;
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  // Le libellé est directement l'unité du produit choisi (g, ml…), sans le mot
                  // « Dose » ni parenthèses ; « Quantité » si aucune unité exploitable.
                  labelText: _unitLabel(selectedRef?.unit),
                ),
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
                            dose: _doseWithUnit(
                              doseController.text,
                              selectedRef!.unit,
                            ),
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
    bool missing = false,
    Key? fieldWidgetKey,
  }) {
    return TextFormField(
      key: fieldWidgetKey,
      initialValue: value?.toString() ?? '',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: _fieldDecoration(label, missing: missing),
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
                    value: _consumptionMissing(entry.roomName) ? null : (entry.femaleQuantityKg ?? 0),
                    missing: _consumptionMissing(entry.roomName),
                    fieldWidgetKey: ValueKey('c:${entry.roomName}:$i:f:$_zeroEpoch'),
                    onChanged: (v) => setState(() {
                      if (v != null) _confirmed.add('c:${entry.roomName}');
                      _consumption[i] = entry.copyWith(femaleQuantityKg: v ?? 0);
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _numberField(
                    label: 'Mâles (kg)',
                    value: _consumptionMissing(entry.roomName) ? null : (entry.maleQuantityKg ?? 0),
                    missing: _consumptionMissing(entry.roomName),
                    fieldWidgetKey: ValueKey('c:${entry.roomName}:$i:m:$_zeroEpoch'),
                    onChanged: (v) => setState(() {
                      if (v != null) _confirmed.add('c:${entry.roomName}');
                      _consumption[i] = entry.copyWith(maleQuantityKg: v ?? 0);
                    }),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// [fieldKey] : si fourni, le champ est rouge tant qu'il vaut 0 sans avoir été confirmé ;
  /// toute saisie (même 0) le confirme.
  Widget _intField(String label, int value, ValueChanged<int> onChanged, {String? fieldKey}) {
    final missing = fieldKey != null && _zeroUnconfirmed(fieldKey, value);
    return TextFormField(
      // Pas de « 0 » automatique : vide = pas encore renseigné ; 0 doit être saisi.
      key: fieldKey != null ? ValueKey('$fieldKey:$_zeroEpoch') : null,
      initialValue: missing ? '' : value.toString(),
      keyboardType: TextInputType.number,
      decoration: _fieldDecoration(label, missing: missing),
      onChanged: (v) {
        if (fieldKey != null) {
          if (v.trim().isEmpty) {
            _confirmed.remove(fieldKey);
          } else {
            _confirmed.add(fieldKey);
          }
        }
        onChanged(int.tryParse(v) ?? 0);
      },
    );
  }

  InputDecoration _fieldDecoration(String label, {bool missing = false}) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: missing,
      fillColor: missing ? Colors.red.shade50 : null,
      labelStyle: missing ? TextStyle(color: Colors.red.shade700) : null,
      border: const OutlineInputBorder(),
      enabledBorder: missing
          ? OutlineInputBorder(borderSide: BorderSide(color: Colors.red.shade300, width: 1.5))
          : null,
    );
  }

  /// [fieldKey] : si fourni, trois états — rouge (0 non confirmé = oubli possible), vert avec
  /// coche (0 confirmé), jaune (valeur > 0). Toucher le chiffre confirme 0.
  Widget _stepperField({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
    String? fieldKey,
  }) {
    final active = value > 0;
    final missing = fieldKey != null && _zeroUnconfirmed(fieldKey, value);
    final confirmedZero = fieldKey != null && value == 0 && _confirmed.contains(fieldKey);
    void emit(int v) {
      if (fieldKey != null) _confirmed.add(fieldKey);
      onChanged(v);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: missing
            ? Colors.red.shade50
            : confirmedZero
                ? DailyReportColors.green100
                : active
                    ? DailyReportColors.yellow100
                    : DailyReportColors.surface,
        border: Border.all(
          color: missing
              ? Colors.red.shade300
              : confirmedZero
                  ? DailyReportColors.green600
                  : active
                      ? DailyReportColors.yellow500
                      : Colors.grey.shade300,
          width: missing ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      // Libellé au-dessus, boutons dessous : en demi-largeur, la ligne unique
      // débordait et le « + » du champ de gauche passait sous le champ voisin.
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: missing ? Colors.red.shade700 : null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
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
                onPressed: value > 0 ? () => emit(value - 1) : null,
              ),
              // Toucher le chiffre = confirmer « 0 » sans avoir à faire +/−.
              GestureDetector(
                onTap: fieldKey != null && value == 0
                    ? () => setState(() => _confirmed.add(fieldKey))
                    : null,
                child: SizedBox(
                  width: 30,
                  child: Text(
                    missing ? '–' : '$value',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: missing
                          ? Colors.red.shade700
                          : active
                              ? DailyReportColors.yellow600
                              : DailyReportColors.green900,
                    ),
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
                onPressed: () => emit(value + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
