import 'package:flutter/material.dart';
import '../models/user.dart';
import '../models/lot.dart';
import '../models/weighing_session.dart';
import '../services/mongo_service.dart';
import '../services/session_storage.dart';

class WeighingSummaryScreen extends StatefulWidget {
  final User user;
  final Lot lot;
  final String operator;
  final String building;
  final String room;
  final int age;
  final List<double> weights;

  const WeighingSummaryScreen({
    super.key,
    required this.user,
    required this.lot,
    required this.operator,
    required this.building,
    required this.room,
    required this.age,
    required this.weights,
  });

  @override
  State<WeighingSummaryScreen> createState() => _WeighingSummaryScreenState();
}

class _WeighingSummaryScreenState extends State<WeighingSummaryScreen> {
  final MongoService _mongoService = MongoService();
  bool _isSaving = false;

  late double _averageWeight;
  late double _plus10;
  late double _minus10;
  late int _homogeneousCount;
  late double _homogeneityPercentage;

  @override
  void initState() {
    super.initState();
    _calculateStats();
  }

  void _calculateStats() {
    if (widget.weights.isEmpty) return;

    double sum = widget.weights.reduce((a, b) => a + b);
    _averageWeight = sum / widget.weights.length;
    
    _plus10 = _averageWeight * 1.10;
    _minus10 = _averageWeight * 0.90;

    _homogeneousCount = widget.weights.where((w) => w >= _minus10 && w <= _plus10).length;
    _homogeneityPercentage = (_homogeneousCount / widget.weights.length) * 100;
  }

  Future<void> _confirmAndSave() async {
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
        content: const Text(
          'Êtes-vous sûr de vouloir enregistrer définitivement cette session de pesée ?\n\nCette action est irréversible.',
          style: TextStyle(fontSize: 14),
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
        lotId: widget.lot.id ?? widget.lot.number,
        operator: widget.operator,
        farmName: widget.building,
        roomName: widget.room,
        age: widget.age,
        weights: widget.weights,
        timestamp: DateTime.now(),
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
      
      Navigator.of(context).pop();
      Navigator.of(context).pop();
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de l\'enregistrement: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RÉSUMÉ DE LA PESÉE', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Informations Générales'),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildInfoRow('Opérateur', widget.operator, Icons.person),
                    _buildInfoRow('Lot', widget.lot.number, Icons.inventory_2),
                    _buildInfoRow('Bâtiment', widget.building, Icons.agriculture),
                    _buildInfoRow('Salle', widget.room, Icons.room),
                    _buildInfoRow('Âge', '${widget.age} semaines', Icons.calendar_today),
                    _buildInfoRow('Nombre de sujets', '${widget.weights.length}', Icons.numbers),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Statistiques de Performance'),
            Card(
              color: Colors.orange.shade50,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.orange.shade200)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    _buildStatItem('Poids Moyen', '${_averageWeight.toStringAsFixed(2)} g', Colors.black),
                    const Divider(),
                    Row(
                      children: [
                        Expanded(child: _buildStatItem('PM - 10%', '${_minus10.toStringAsFixed(2)} g', Colors.red)),
                        Expanded(child: _buildStatItem('PM + 10%', '${_plus10.toStringAsFixed(2)} g', Colors.blue)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          const Text('HOMOGÉNÉITÉ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 5),
                          Text(
                            '${_homogeneityPercentage.toStringAsFixed(1)} %',
                            style: TextStyle(
                              fontSize: 32, 
                              fontWeight: FontWeight.bold, 
                              color: _homogeneityPercentage >= 80 ? Colors.green : Colors.orange,
                            ),
                          ),
                          Text(
                            '$_homogeneousCount sujets homogènes',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Détail des Poids (${widget.weights.length} sujets)'),
            Container(
              height: 200,
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Scrollbar(
                thumbVisibility: true,
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 60,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    childAspectRatio: 2,
                  ),
                  itemCount: widget.weights.length,
                  itemBuilder: (context, index) {
                    final w = widget.weights[index];
                    final isHomogeneous = (w >= _minus10 && w <= _plus10);
                    return Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isHomogeneous ? Colors.green.shade50 : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isHomogeneous ? Colors.green.shade200 : Colors.red.shade200,
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        '${w.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isHomogeneous ? Colors.green.shade800 : Colors.red.shade800,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: _isSaving ? null : () => _confirmAndSave(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: _isSaving 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('ENREGISTRER DÉFINITIVEMENT', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.orange),
          const SizedBox(width: 10),
          Text('$label :', style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
