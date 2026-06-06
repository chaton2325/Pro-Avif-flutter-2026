import 'package:flutter/material.dart';
import '../models/weighing_session.dart';

class WeighingHistoryDetailScreen extends StatelessWidget {
  final WeighingSession session;

  const WeighingHistoryDetailScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    // Re-calculate statistics locally for display
    double sum = session.weights.reduce((a, b) => a + b);
    double averageWeight = sum / session.weights.length;
    double plus10 = averageWeight * 1.10;
    double minus10 = averageWeight * 0.90;
    int homogeneousCount = session.weights.where((w) => w >= minus10 && w <= plus10).length;
    double homogeneityPercentage = (homogeneousCount / session.weights.length) * 100;

    return Scaffold(
      appBar: AppBar(
        title: Text('PESÉE LOT: ${session.lotId}', style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Info
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildInfoRow('Opérateur', session.operator, Icons.person),
                    _buildInfoRow('Bâtiment', session.farmName, Icons.agriculture),
                    _buildInfoRow('Salle', session.roomName, Icons.room),
                    _buildInfoRow('Âge', '${session.age} semaines', Icons.calendar_today),
                    _buildInfoRow('Date', '${session.timestamp.day}/${session.timestamp.month}/${session.timestamp.year} ${session.timestamp.hour}:${session.timestamp.minute.toString().padLeft(2, '0')}', Icons.access_time),
                    _buildInfoRow('Status', session.isSync ? 'Synchronisé' : 'Stockage Local', session.isSync ? Icons.cloud_done : Icons.cloud_off),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Statistics Card
            const Text('Statistiques', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 8),
            Card(
              color: Colors.orange.shade50,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.orange.shade200)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    _buildStatItem('Poids Moyen', '${averageWeight.toStringAsFixed(2)} g', Colors.black),
                    const Divider(),
                    Row(
                      children: [
                        Expanded(child: _buildStatItem('PM - 10%', '${minus10.toStringAsFixed(2)} g', Colors.red)),
                        Expanded(child: _buildStatItem('PM + 10%', '${plus10.toStringAsFixed(2)} g', Colors.blue)),
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
                            '${homogeneityPercentage.toStringAsFixed(1)} %',
                            style: TextStyle(
                              fontSize: 32, 
                              fontWeight: FontWeight.bold, 
                              color: homogeneityPercentage >= 80 ? Colors.green : Colors.orange,
                            ),
                          ),
                          Text(
                            '$homogeneousCount sujets homogènes / ${session.weights.length}',
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

            // All Weights Grid
            Text('Détail des Poids (${session.weights.length} sujets)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 8),
            Container(
              height: 300,
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
                  itemCount: session.weights.length,
                  itemBuilder: (context, index) {
                    final w = session.weights[index];
                    final isHomogeneous = (w >= minus10 && w <= plus10);
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
          ],
        ),
      ),
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
