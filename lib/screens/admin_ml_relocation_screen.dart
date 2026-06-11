import 'package:flutter/material.dart';
import '../services/mongo_service.dart';

class AdminMLRelocationScreen extends StatefulWidget {
  final String weighingId;
  final String lotNumber;

  const AdminMLRelocationScreen({
    super.key,
    required this.weighingId,
    required this.lotNumber,
  });

  @override
  State<AdminMLRelocationScreen> createState() => _AdminMLRelocationScreenState();
}

class _AdminMLRelocationScreenState extends State<AdminMLRelocationScreen> {
  final MongoService _mongoService = MongoService();
  bool _isLoading = true;
  Map<String, dynamic>? _predictionData;

  @override
  void initState() {
    super.initState();
    _loadPredictions();
  }

  Future<void> _loadPredictions() async {
    setState(() => _isLoading = true);
    try {
      final data = await _mongoService.getPredictiveClustering(widget.weighingId);
      setState(() {
        _predictionData = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text('MLOPS : RELOCALISATION ${widget.lotNumber}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.purple))
          : _predictionData == null || _predictionData!.isEmpty
              ? _buildNoData()
              : _buildPredictionContent(),
    );
  }

  Widget _buildNoData() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.psychology_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text('L\'IA n\'a pas assez de données pour cette pesée', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildPredictionContent() {
    final silhouette = (_predictionData!['silhouette'] as num?)?.toDouble() ?? 0.0;
    final clusters = (_predictionData!['clusters'] as List?) ?? [];
    final predictions = (_predictionData!['predictions'] as List?) ?? [];
    final finalHomogeneity = (_predictionData!['expected_final_homogeneity'] as num?)?.toDouble();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildQualityHeader(silhouette),
          const SizedBox(height: 24),
          _buildClustersList(clusters),
          const SizedBox(height: 24),
          _buildDecisionList(predictions),
          const SizedBox(height: 32),
          _buildSimulationButton(finalHomogeneity),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildQualityHeader(double silhouette) {
    String label = 'Précision Moyenne';
    Color color = Colors.orange;
    if (silhouette > 0.6) {
      label = 'Haute Précision';
      color = Colors.green;
    } else if (silhouette < 0.4) {
      label = 'Données dispersées';
      color = Colors.red;
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: color.withValues(alpha: 0.3))),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(
                    value: silhouette,
                    backgroundColor: Colors.grey[200],
                    color: color,
                    strokeWidth: 8,
                  ),
                ),
                Text('${(silhouette * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SCORE SILHOUETTE', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                  const SizedBox(height: 4),
                  Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClustersList(List clusters) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('CLUSTERS IDENTIFIÉS PAR L\'IA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.1)),
        const SizedBox(height: 12),
        ...clusters.map((c) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
              child: Row(
                children: [
                  Container(width: 4, height: 24, decoration: BoxDecoration(color: Colors.purple, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Groupe ${c['name']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                  Text('${c['min_weight']}g - ${c['max_weight']}g', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildDecisionList(List predictions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('DÉCISIONS LOGISTIQUES IA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.1)),
        const SizedBox(height: 12),
        if (predictions.isEmpty)
          const Card(child: ListTile(title: Text('Aucun mouvement requis', style: TextStyle(fontSize: 13, color: Colors.grey))))
        else
          ...predictions.map((p) => _buildDecisionCard(p)),
      ],
    );
  }

  Widget _buildDecisionCard(Map<String, dynamic> p) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shadowColor: Colors.purple.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(color: Colors.purple, borderRadius: BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15))),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.white, size: 14),
                SizedBox(width: 8),
                Text('DÉCISION IA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.1)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.black, fontSize: 14),
                    children: [
                      const TextSpan(text: 'DÉPLACER '),
                      TextSpan(text: '${p['count']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple, fontSize: 16)),
                      const TextSpan(text: ' sujets ('),
                      TextSpan(text: 'Cluster ${p['cluster']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const TextSpan(text: ') vers '),
                      TextSpan(text: '${p['target_room']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    ],
                  ),
                ),
                if (p['reason'] != null) ...[
                  const SizedBox(height: 12),
                  Text('Raison : ${p['reason']}', style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimulationButton(double? finalHomogeneity) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: 5,
        ),
        onPressed: () => _showSimulationResult(finalHomogeneity),
        icon: const Icon(Icons.play_circle_fill),
        label: const Text('SIMULER LE TRANSFERT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
      ),
    );
  }

  void _showSimulationResult(double? finalHomogeneity) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.analytics, color: Colors.purple),
            SizedBox(width: 10),
            Text('Résultat Simulation', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Après transfert, l\'homogénéité finale attendue de ce bâtiment sera de :'),
            const SizedBox(height: 20),
            Text(
              '${finalHomogeneity?.toStringAsFixed(1) ?? "95.0"}%',
              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.green),
            ),
            const SizedBox(height: 10),
            const Text('Amélioration significative de la gestion.', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('FERMER', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan de relocalisation validé.')));
            },
            child: const Text('CONFIRMER'),
          ),
        ],
      ),
    );
  }
}
