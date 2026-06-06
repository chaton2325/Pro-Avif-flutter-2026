import 'package:flutter/material.dart';
import '../models/user.dart';
import '../models/lot.dart';
import '../services/session_storage.dart';
import 'weight_entry_screen.dart';

class PendingSessionsScreen extends StatefulWidget {
  final User user;

  const PendingSessionsScreen({super.key, required this.user});

  @override
  State<PendingSessionsScreen> createState() => _PendingSessionsScreenState();
}

class _PendingSessionsScreenState extends State<PendingSessionsScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    final sessions = await SessionStorage.getSessionsForUser(widget.user.id!);
    setState(() {
      _sessions = sessions;
      _isLoading = false;
    });
  }

  void _resumeSession(Map<String, dynamic> sessionData) {
    final lot = Lot.fromMap(sessionData['lot']);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WeightEntryScreen(
          user: widget.user,
          lot: lot,
          operator: sessionData['operator'],
          building: sessionData['building'],
          room: sessionData['room'],
          age: sessionData['age'],
          minWeight: sessionData['minWeight'].toDouble(),
          maxWeight: sessionData['maxWeight'].toDouble(),
          precision: sessionData['precision'],
          initialWeights: List<double>.from(sessionData['weights'].map((x) => x.toDouble())),
        ),
      ),
    ).then((_) => _loadSessions());
  }

  Future<void> _deleteSession(Map<String, dynamic> sessionData) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la session ?'),
        content: const Text('Cette opération de pesée sera définitivement perdue.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ANNULER')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('SUPPRIMER', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await SessionStorage.clearSession(
        widget.user.id!,
        sessionData['lot']['number'],
        sessionData['room'],
        sessionData['building'],
      );
      _loadSessions();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PESÉES EN ATTENTE', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : _sessions.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('Aucune pesée en attente', style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _sessions.length,
                  itemBuilder: (context, index) {
                    final session = _sessions[index];
                    final date = DateTime.parse(session['timestamp']);
                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: CircleAvatar(
                          backgroundColor: Colors.red.shade100,
                          child: Icon(Icons.timer_outlined, color: Colors.red.shade700),
                        ),
                        title: Text(
                          'Lot: ${session['lot']['number']}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${session['building']} - ${session['room']}'),
                            const SizedBox(height: 4),
                            Text(
                              '${session['weights'].length} poids enregistrés',
                              style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Interrompue le ${date.day}/${date.month} à ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.grey),
                          onPressed: () => _deleteSession(session),
                        ),
                        onTap: () => _resumeSession(session),
                      ),
                    );
                  },
                ),
    );
  }
}
