import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/user.dart';
import '../models/lot.dart';
import '../models/weighing_session.dart';
import '../services/mongo_service.dart';
import '../services/session_storage.dart';
import 'weighing_summary_screen.dart';

class WeightEntryScreen extends StatefulWidget {
  final User user;
  final Lot lot;
  final String operator;
  final String building;
  final String room;
  final int age;
  final String? sex;
  final double minWeight;
  final double maxWeight;
  final int precision;
  final List<double>? initialWeights;

  const WeightEntryScreen({
    super.key,
    required this.user,
    required this.lot,
    required this.operator,
    required this.building,
    required this.room,
    required this.age,
    this.sex,
    required this.minWeight,
    required this.maxWeight,
    required this.precision,
    this.initialWeights,
  });

  @override
  State<WeightEntryScreen> createState() => _WeightEntryScreenState();
}

class _WeightEntryScreenState extends State<WeightEntryScreen> {
  final TextEditingController _weightController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final MongoService _mongoService = MongoService();
  late List<double> _weights;
  String? _errorMessage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _weights = widget.initialWeights != null ? List.from(widget.initialWeights!) : [];
  }

  void _persistLocally() {
    SessionStorage.saveSession(
      user: widget.user,
      lot: widget.lot,
      operator: widget.operator,
      building: widget.building,
      room: widget.room,
      sex: widget.sex,
      lowerInterval: widget.minWeight,
      upperInterval: widget.maxWeight,
      age: widget.age,
      minWeight: widget.minWeight,
      maxWeight: widget.maxWeight,
      precision: widget.precision,
      weights: _weights,
    );
  }

  void _addWeight() {
    final String valueStr = _weightController.text.trim();
    if (valueStr.isEmpty) return;

    final double? weight = double.tryParse(valueStr);
    
    if (weight == null) {
      _setTemporaryError("Format invalide");
      return;
    }

    if (weight < widget.minWeight || weight > widget.maxWeight) {
      _setTemporaryError("Hors intervalle (${widget.minWeight} - ${widget.maxWeight})");
      return;
    }

    if (weight % widget.precision != 0) {
      _setTemporaryError("Doit être un multiple de ${widget.precision}");
      return;
    }

    setState(() {
      _weights.add(weight);
      _weightController.clear();
      _errorMessage = null;
    });

    _persistLocally();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  double _computeHomogeneity() {
    if (_weights.isEmpty) return 0;
    final double average = _weights.reduce((a, b) => a + b) / _weights.length;
    final double plus10 = average * 1.10;
    final double minus10 = average * 0.90;
    final int homogeneousCount = _weights.where((w) => w >= minus10 && w <= plus10).length;
    return (homogeneousCount / _weights.length) * 100;
  }

  Future<void> _confirmAndSave() async {
    if (_weights.isEmpty) return;

    String? duplicateWarning;
    try {
      final dup = await _mongoService.checkDuplicateWeighing(
        farmName: widget.building,
        roomName: widget.room,
        sex: widget.sex ?? '',
        lotId: widget.lot.id ?? widget.lot.number,
        age: widget.age,
      );
      if (dup['exists'] == true) {
        String dateStr = '';
        final lastTs = dup['lastTimestamp'];
        if (lastTs != null) {
          final d = DateTime.tryParse(lastTs.toString());
          if (d != null) dateStr = ' (le ${DateFormat('dd/MM/yyyy').format(d)})';
        }
        duplicateWarning =
            'Une pesée existe déjà cette semaine pour ce lot$dateStr.\nCette nouvelle pesée sera considérée comme la plus récente dans les graphiques ; l\'ancienne restera visible dans l\'historique.\n\n';
      }
    } catch (_) {
      // Si la vérification échoue (ex: hors-ligne), on continue sans bloquer la saisie.
    }

    if (!mounted) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 10),
            Text('Confirmation', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          '${duplicateWarning ?? ''}Êtes-vous sûr de vouloir enregistrer définitivement la pesée de ce mois ?\n\nCette action est irréversible.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ANNULER', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('OUI, ENREGISTRER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _saveSession();
    }
  }

  Future<void> _saveSession() async {
    setState(() => _isSaving = true);

    try {
      final session = WeighingSession(
        userId: widget.user.id!,
        lotId: widget.lot.id ?? widget.lot.number,
        lotNumber: widget.lot.number,
        operator: widget.operator,
        farmName: widget.building,
        roomName: widget.room,
        sex: widget.sex,
        lowerInterval: widget.minWeight,
        upperInterval: widget.maxWeight,
        age: widget.age,
        weights: _weights,
        timestamp: DateTime.now(),
        homogeneity: _computeHomogeneity(),
      );

      await _mongoService.saveWeighingSession(session);
      await SessionStorage.clearSession(
        widget.user.id!,
        widget.lot.number,
        widget.room,
        widget.building,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session enregistrée avec succès !'), backgroundColor: Colors.green),
      );

      _goToSummary();
    } catch (e) {
      if (!mounted) return;

      if (e.toString().contains("OFFLINE_SAVED")) {
        await SessionStorage.clearSession(
          widget.user.id!,
          widget.lot.number,
          widget.room,
          widget.building,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mode Hors-Ligne : Pesée sauvegardée localement. Elle sera synchronisée à votre prochaine connexion.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
        _goToSummary();
      } else {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de l\'enregistrement: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _goToSummary() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => WeighingSummaryScreen(
          user: widget.user,
          lot: widget.lot,
          operator: widget.operator,
          building: widget.building,
          room: widget.room,
          age: widget.age,
          sex: widget.sex,
          lowerInterval: widget.minWeight,
          upperInterval: widget.maxWeight,
          weights: _weights,
        ),
      ),
    );
  }

  void _setTemporaryError(String msg) {
    setState(() {
      _errorMessage = msg;
    });
  }

  void _removeWeight(int index) {
    setState(() {
      _weights.removeAt(index);
    });
    _persistLocally();
  }

  @override
  void dispose() {
    _weightController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SAISIE DES POIDS', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Info Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.orange.withValues(alpha: 0.05),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildHeaderInfo("Lot", widget.lot.number),
                    _buildHeaderInfo("Salle", widget.room),
                    _buildHeaderInfo("Précision", "${widget.precision}g"),
                  ],
                ),
                const Divider(),
                Text(
                  "Intervalle : ${widget.minWeight}g - ${widget.maxWeight}g",
                  style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          // Weights Area (Scrollable)
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border.symmetric(horizontal: BorderSide(color: Colors.grey.shade200)),
              ),
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _weights.asMap().entries.map((entry) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 2, offset: const Offset(0, 1)),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            entry.value.toStringAsFixed(0),
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => _removeWeight(entry.key),
                            child: const Icon(Icons.close, size: 12, color: Colors.white60),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),

          // Input Area (Fixed above keyboard)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 15, 20, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5)),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _weightController,
                        keyboardType: TextInputType.number,
                        autofocus: true,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: 'Entrer un poids (g)',
                          errorText: _errorMessage,
                          errorStyle: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onSubmitted: (_) => _addWeight(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 55,
                      width: 55,
                      child: ElevatedButton(
                        onPressed: _addWeight,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Icon(Icons.add, color: Colors.white, size: 30),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "Nombre de pesées : ${_weights.length}",
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 13),
                ),
              ],
            ),
          ),

          // Footer Action
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: (_weights.isEmpty || _isSaving) ? null : _confirmAndSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.save, color: Colors.white, size: 20),
                label: const Text('ENREGISTRER', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderInfo(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }
}
