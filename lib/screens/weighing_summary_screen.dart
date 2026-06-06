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
      
      // Go back to dashboard (Pop Summary -> Pop Entry -> Pop NewWeighing)
      Navigator.of(context).pop(); // Back to Entry
      Navigator.of(context).pop(); // Back to NewWeighing (if from there) or Dashboard
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(); // Ensure we are at Dashboard
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
            // Session Info Card
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

            // Statistics Card
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

            // Weights List (Preview)
            _buildSectionTitle('Détail des Poids'),
            Container(
              height: 150,
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.weights.map((w) => Chip(
                    label: Text('${w.toStringAsFixed(0)}g', style: const TextStyle(fontSize: 11)),
                    backgroundColor: (w >= _minus10 && w <= _plus10) ? Colors.green.shade50 : Colors.red.shade50,
                  )).toList(),
                ),
              ),
            ),
            const SizedBox(height: 40),

            // Final Save Button
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveSession,
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
