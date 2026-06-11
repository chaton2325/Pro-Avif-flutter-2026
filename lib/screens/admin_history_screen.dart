import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/weighing_session.dart';
import '../services/mongo_service.dart';
import 'weighing_history_detail_screen.dart';

class AdminHistoryScreen extends StatefulWidget {
  const AdminHistoryScreen({super.key});

  @override
  State<AdminHistoryScreen> createState() => _AdminHistoryScreenState();
}

class _AdminHistoryScreenState extends State<AdminHistoryScreen> {
  final MongoService _mongoService = MongoService();
  final ScrollController _scrollController = ScrollController();
  
  List<WeighingSession> _sessions = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _skip = 0;
  final int _limit = 20;
  
  String _sortBy = 'timestamp';
  String _order = 'desc';

  @override
  void initState() {
    super.initState();
    _loadSessions(clear: true);
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) {
        _loadSessions();
      }
    }
  }

  Future<void> _loadSessions({bool clear = false}) async {
    if (clear) {
      setState(() {
        _skip = 0;
        _sessions = [];
        _hasMore = true;
      });
    }
    
    setState(() => _isLoading = true);
    
    final result = await _mongoService.getPaginatedWeighings(
      skip: _skip,
      limit: _limit,
      sortBy: _sortBy,
      order: _order,
    );

    final List<dynamic> data = result['data'];
    final List<WeighingSession> newSessions = data.map((s) => WeighingSession.fromMap(s)).toList();
    
    if (!mounted) return;
    
    setState(() {
      _sessions.addAll(newSessions);
      _skip += newSessions.length;
      _isLoading = false;
      _hasMore = newSessions.length == _limit;
    });
  }

  void _updateSort(String sortBy, String order) {
    setState(() {
      _sortBy = sortBy;
      _order = order;
    });
    _loadSessions(clear: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HISTORIQUE GLOBAL'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadSessions(clear: true),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSortBar(),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _sessions.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _sessions.length) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _buildAdminSessionCard(_sessions[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.grey[200],
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _sortBy,
              decoration: const InputDecoration(labelText: 'Trier par', contentPadding: EdgeInsets.symmetric(horizontal: 10)),
              items: const [
                DropdownMenuItem(value: 'timestamp', child: Text('Date')),
                DropdownMenuItem(value: 'lotId', child: Text('Lot')),
                DropdownMenuItem(value: 'homogeneity', child: Text('Homogénéité')),
                DropdownMenuItem(value: 'operator', child: Text('Opérateur')),
                DropdownMenuItem(value: 'farmName', child: Text('Site')),
              ],
              onChanged: (val) => _updateSort(val!, _order),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _order,
              decoration: const InputDecoration(labelText: 'Ordre', contentPadding: EdgeInsets.symmetric(horizontal: 10)),
              items: const [
                DropdownMenuItem(value: 'desc', child: Text('Décroissant ↓')),
                DropdownMenuItem(value: 'asc', child: Text('Croissant ↑')),
              ],
              onChanged: (val) => _updateSort(_sortBy, val!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminSessionCard(WeighingSession session) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WeighingHistoryDetailScreen(session: session))),
        title: Text('Lot: ${session.lotNumber ?? session.lotId}', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('${session.farmName} • ${session.operator}'),
            const SizedBox(height: 2),
            Row(
              children: [
                if (session.sex != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      session.sex!,
                      style: TextStyle(fontSize: 10, color: Colors.blue.shade800, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  DateFormat('dd/MM HH:mm').format(session.timestamp),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${session.homogeneity.toStringAsFixed(1)}%',
              style: TextStyle(
                fontWeight: FontWeight.bold, 
                fontSize: 16,
                color: session.homogeneity >= 80 ? Colors.green : Colors.orange,
              ),
            ),
            const Text('Homog.', style: TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
