import 'package:flutter/material.dart';
import '../models/user.dart';
import '../models/weighing_session.dart';
import '../services/mongo_service.dart';
import '../services/session_storage.dart';
import 'weighing_history_detail_screen.dart';

class UserHistoryScreen extends StatefulWidget {
  final User user;

  const UserHistoryScreen({super.key, required this.user});

  @override
  State<UserHistoryScreen> createState() => _UserHistoryScreenState();
}

class _UserHistoryScreenState extends State<UserHistoryScreen> {
  final MongoService _mongoService = MongoService();
  List<WeighingSession> _serverSessions = [];
  List<WeighingSession> _offlineSessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    
    // Load offline
    final offline = await SessionStorage.getOfflineSessions();
    
    // Load server
    final server = await _mongoService.getUserWeighings(widget.user.id!);
    
    if (!mounted) return;
    setState(() {
      _offlineSessions = offline;
      _serverSessions = server;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final allSessions = [..._offlineSessions, ..._serverSessions];
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('MON HISTORIQUE', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadHistory),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.orange))
        : allSessions.isEmpty
          ? const Center(child: Text('Aucune pesée enregistrée', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: allSessions.length,
              itemBuilder: (context, index) {
                final session = allSessions[index];
                return _buildSessionCard(session);
              },
            ),
    );
  }

  Widget _buildSessionCard(WeighingSession session) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WeighingHistoryDetailScreen(session: session),
            ),
          );
        },
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: session.isSync ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
          child: Icon(
            session.isSync ? Icons.cloud_done : Icons.cloud_off,
            color: session.isSync ? Colors.green : Colors.orange,
          ),
        ),
        title: Text('Lot: ${session.lotId}', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${session.farmName} - ${session.roomName}'),
            Text('${session.weights.length} sujets | PM: ${(session.weights.reduce((a, b) => a + b) / session.weights.length).toStringAsFixed(1)}g'),
            Text(
              'Le ${session.timestamp.day}/${session.timestamp.month} à ${session.timestamp.hour}:${session.timestamp.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: session.isSync ? Colors.green.shade50 : Colors.orange.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            session.isSync ? 'SYNC' : 'LOCAL',
            style: TextStyle(
              fontSize: 10, 
              fontWeight: FontWeight.bold, 
              color: session.isSync ? Colors.green : Colors.orange,
            ),
          ),
        ),
      ),
    );
  }
}
