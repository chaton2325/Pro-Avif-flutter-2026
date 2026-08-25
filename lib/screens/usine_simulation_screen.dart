import 'package:flutter/material.dart';
import '../models/usine.dart';
import '../models/raw_material.dart';
import '../models/simulation.dart';
import '../models/poste.dart';
import '../models/feed_stock.dart';
import '../services/mongo_service.dart';

/// Parcours 03 — Simulation & optimisation (maquette écrans 20-21), repensé en UNE seule
/// page qui se lit de haut en bas (l'ancienne version à 2 onglets séparés perdait
/// l'utilisateur) : 1) le stock actuel, 2) ce qu'on peut fabriquer avec (un aliment à la
/// fois), 3) la meilleure répartition si on veut en fabriquer plusieurs en même temps.
/// Vocabulaire volontairement simple — pas de « programmation linéaire » ni de jargon
/// technique à l'écran, juste la conséquence concrète pour l'utilisateur.
class UsineSimulationScreen extends StatefulWidget {
  final Usine usine;
  final PostePermissions? permissions;
  const UsineSimulationScreen({
    super.key,
    required this.usine,
    this.permissions,
  });

  @override
  State<UsineSimulationScreen> createState() => _UsineSimulationScreenState();
}

class _UsineSimulationScreenState extends State<UsineSimulationScreen> {
  final MongoService _mongoService = MongoService();
  PostePermissions get _perms => widget.permissions ?? fullAccessPermissions;

  List<RawMaterial> _materials = [];
  List<FeedStockSummary> _ingredientStocks = [];
  List<SimulationLine> _simulation = [];
  OptimizationResult? _optimization;
  String? _optimizationError;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    final materials = await _mongoService.getRawMaterials(widget.usine.id!);
    final formulas = await _mongoService.getFormulas(widget.usine.id!);
    final feedStock = await _mongoService.getFeedStock(widget.usine.id!);
    final sim = await _mongoService.simulateProduction(widget.usine.id!);
    final opt = await _mongoService.optimizeProduction(widget.usine.id!);
    if (!mounted) return;
    // Un aliment (ex. SUPER PLUS) n'apparaît ici que s'il sert vraiment d'ingrédient à une
    // formule active — inutile d'afficher le stock de tous les aliments produits, juste
    // ceux qui pèsent réellement sur ce qu'on peut fabriquer.
    final ingredientIds = formulas
        .where((f) => f.isActive)
        .expand((f) => f.lines)
        .where((l) => l.isIngredientAliment)
        .map((l) => l.ingredientFormulaId)
        .toSet();
    setState(() {
      _materials = materials.where((m) => m.isActive).toList();
      _ingredientStocks = feedStock
          .where((s) => ingredientIds.contains(s.formulaId))
          .toList();
      _simulation = sim;
      _optimization = opt.result;
      _optimizationError = opt.error;
      _isLoading = false;
    });
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'rupture':
        return Colors.grey.shade600;
      case 'limite':
        return Colors.orange.shade800;
      default:
        return Colors.green.shade700;
    }
  }

  Color _statusBg(String status) {
    switch (status) {
      case 'rupture':
        return Colors.grey.shade200;
      case 'limite':
        return Colors.amber.shade100;
      default:
        return Colors.green.shade100;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'rupture':
        return 'RUPTURE';
      case 'limite':
        return 'BIENTÔT LIMITE';
      default:
        return 'OK';
    }
  }

  Widget _sectionHeader(String emoji, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  // ---------------------------------------------------------- Section 1 : stock actuel

  Widget _buildStockSection() {
    if (_materials.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            '📦',
            'Stock des matières premières',
            'Ce que vous avez en ce moment',
          ),
          _card(
            child: Column(
              children: _materials.map((m) {
                final hasThreshold = m.lowStockThreshold > 0;
                final isLow =
                    hasThreshold && m.currentStock < m.lowStockThreshold;
                final isEmpty = m.currentStock <= 0;
                final color = isEmpty
                    ? Colors.grey.shade500
                    : (isLow ? Colors.orange.shade800 : Colors.green.shade700);
                final ratio = hasThreshold
                    ? (m.currentStock / (m.lowStockThreshold * 3)).clamp(
                        0.0,
                        1.0,
                      )
                    : (m.currentStock > 0 ? 1.0 : 0.0);
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              m.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          Text(
                            '${m.currentStock.toStringAsFixed(0)} ${m.unit}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 6,
                          backgroundColor: Colors.grey.shade100,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------- Section 1bis : aliments utilisés en ingrédient

  Widget _buildIngredientStockSection() {
    if (_ingredientStocks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            '🏭',
            'Aliments utilisés comme ingrédient',
            'Un aliment déjà fabriqué (ex. SUPER PLUS) qui entre dans un autre',
          ),
          _card(
            child: Column(
              children: _ingredientStocks.map((s) {
                final hasThreshold = s.lowStockThreshold > 0;
                final isLow =
                    hasThreshold && s.totalStock < s.lowStockThreshold;
                final isEmpty = s.totalStock <= 0;
                final color = isEmpty
                    ? Colors.grey.shade500
                    : (isLow ? Colors.orange.shade800 : Colors.green.shade700);
                final ratio = hasThreshold
                    ? (s.totalStock / (s.lowStockThreshold * 3)).clamp(0.0, 1.0)
                    : (s.totalStock > 0 ? 1.0 : 0.0);
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.formulaName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          Text(
                            '${s.totalStock.toStringAsFixed(0)} kg',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 6,
                          backgroundColor: Colors.grey.shade100,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------- Section 2 : un aliment à la fois (solo)

  Widget _buildSoloSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            '🏭',
            'Ce que vous pouvez fabriquer',
            'Un seul aliment à la fois, avec le stock ci-dessus',
          ),
          if (_simulation.isEmpty)
            _card(
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Aucune formule active pour cette usine.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ..._simulation.map(
              (l) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.formulaName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                              if (l.limitingMaterialName != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Limité par : ${l.limitingMaterialName}',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '≈ ${l.maxProducibleKg.toStringAsFixed(0)} kg',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                                color: _statusColor(l.status),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _statusBg(l.status),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _statusLabel(l.status),
                                style: TextStyle(
                                  color: _statusColor(l.status),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --------------------------------------- Section 3 : plusieurs aliments à la fois (LP)

  Widget _buildComboSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          '🧮',
          'Meilleure répartition',
          'Si vous fabriquez plusieurs aliments en même temps',
        ),
        _card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: _optimizationError != null
                ? Text(
                    _optimizationError!,
                    style: const TextStyle(color: Colors.grey),
                  )
                : (_optimization == null
                      ? const Text(
                          'Aucune donnée.',
                          style: TextStyle(color: Colors.grey),
                        )
                      : _buildComboContent(_optimization!)),
          ),
        ),
      ],
    );
  }

  Widget _buildComboContent(OptimizationResult opt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Ces aliments se partagent le même stock : c\'est pour ça que les quantités ci-dessous sont parfois plus petites que dans la section précédente.',
            style: TextStyle(fontSize: 11.5, color: Colors.grey),
          ),
        ),
        const SizedBox(height: 14),
        ...opt.plan.map(
          (l) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.formulaName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  l.quantityKg > 0.5
                      ? '${l.quantityKg.toStringAsFixed(0)} kg'
                      : '— (rien)',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: l.quantityKg > 0.5 ? Colors.black87 : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 24),
        const Text(
          'Stock utilisé par matière',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        ...opt.utilization.map(
          (u) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      u.materialName,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${u.utilizationPercent.toStringAsFixed(0)} %',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: u.isLimiting
                            ? Colors.orange.shade800
                            : Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: (u.utilizationPercent / 100).clamp(0, 1),
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade100,
                    color: u.isLimiting ? Colors.amber.shade600 : Colors.green,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (opt.limitingMaterialName != null)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.priority_high_rounded,
                  color: Colors.amber.shade800,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${opt.limitingMaterialName} est utilisé à 100 % : c\'est cette matière qui empêche de produire plus.',
                    style: const TextStyle(fontSize: 12, color: Colors.brown),
                  ),
                ),
              ],
            ),
          ),
        if (opt.wasteAvoidedKg > 0.5)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.savings_outlined,
                  color: Colors.green.shade700,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Cette répartition utilise ${opt.wasteAvoidedKg.toStringAsFixed(0)} kg de stock en plus que si vous partagiez le stock à parts égales entre tous les aliments.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_perms.manageProduction) {
      return Scaffold(
        appBar: AppBar(backgroundColor: Colors.white, elevation: 0),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Réservé au responsable de production.',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'SIMULATION',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: .5,
            fontSize: 13,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.orange),
            onPressed: _refresh,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : RefreshIndicator(
              onRefresh: _refresh,
              color: Colors.orange,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          color: Colors.orange.shade700,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Ceci est une simulation : rien n\'est réservé et aucune fabrication n\'est lancée ici.',
                            style: TextStyle(fontSize: 12, color: Colors.brown),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildStockSection(),
                  _buildIngredientStockSection(),
                  _buildSoloSection(),
                  _buildComboSection(),
                ],
              ),
            ),
    );
  }
}
