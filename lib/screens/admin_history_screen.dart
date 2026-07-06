import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/weighing_session.dart';
import '../models/farm.dart';
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

  List<Farm> _farms = [];
  String? _filterFarm;
  String? _filterRoom;
  String? _filterSex;
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  final TextEditingController _lotController = TextEditingController();
  final TextEditingController _operatorController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSessions(clear: true);
    _scrollController.addListener(_onScroll);
    _mongoService.getFarms().then((farms) {
      if (mounted) setState(() => _farms = farms);
    });
  }

  @override
  void dispose() {
    _lotController.dispose();
    _operatorController.dispose();
    super.dispose();
  }

  List<String> get _roomsForSelectedFarm {
    if (_filterFarm == null) return [];
    final farm = _farms.cast<Farm?>().firstWhere((f) => f?.name == _filterFarm, orElse: () => null);
    return farm?.rooms ?? [];
  }

  void _applyFilters() {
    _loadSessions(clear: true);
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
      farmName: _filterFarm,
      roomName: _filterRoom,
      sex: _filterSex,
      lotNumber: _lotController.text.isEmpty ? null : _lotController.text,
      operator: _operatorController.text.isEmpty ? null : _operatorController.text,
      startDate: _filterStartDate,
      endDate: _filterEndDate,
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
          _buildFilterBar(),
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

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.grey[100],
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  value: _filterFarm,
                  decoration: const InputDecoration(labelText: 'Bâtiment', contentPadding: EdgeInsets.symmetric(horizontal: 10), isDense: true),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Tous')),
                    ..._farms.map((f) => DropdownMenuItem(value: f.name, child: Text(f.name))),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _filterFarm = val;
                      _filterRoom = null;
                    });
                    _applyFilters();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  value: _filterRoom,
                  decoration: const InputDecoration(labelText: 'Salle', contentPadding: EdgeInsets.symmetric(horizontal: 10), isDense: true),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Toutes')),
                    ..._roomsForSelectedFarm.map((r) => DropdownMenuItem(value: r, child: Text(r))),
                  ],
                  onChanged: (val) {
                    setState(() => _filterRoom = val);
                    _applyFilters();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  value: _filterSex,
                  decoration: const InputDecoration(labelText: 'Sexe', contentPadding: EdgeInsets.symmetric(horizontal: 10), isDense: true),
                  items: const [
                    DropdownMenuItem<String?>(value: null, child: Text('Tous')),
                    DropdownMenuItem(value: 'Mâle', child: Text('Mâle')),
                    DropdownMenuItem(value: 'Femelle', child: Text('Femelle')),
                  ],
                  onChanged: (val) {
                    setState(() => _filterSex = val);
                    _applyFilters();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _lotController,
                  decoration: const InputDecoration(labelText: 'Lot', contentPadding: EdgeInsets.symmetric(horizontal: 10), isDense: true),
                  onSubmitted: (_) => _applyFilters(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _operatorController,
                  decoration: const InputDecoration(labelText: 'Opérateur', contentPadding: EdgeInsets.symmetric(horizontal: 10), isDense: true),
                  onSubmitted: (_) => _applyFilters(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.search), onPressed: _applyFilters),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildDateBtn(_filterStartDate, 'Date début', () async {
                  final picked = await showDatePicker(context: context, initialDate: _filterStartDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (picked != null) {
                    setState(() => _filterStartDate = picked);
                    _applyFilters();
                  }
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDateBtn(_filterEndDate, 'Date fin', () async {
                  final picked = await showDatePicker(context: context, initialDate: _filterEndDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (picked != null) {
                    setState(() => _filterEndDate = picked);
                    _applyFilters();
                  }
                }),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    _filterFarm = null;
                    _filterRoom = null;
                    _filterSex = null;
                    _filterStartDate = null;
                    _filterEndDate = null;
                    _lotController.clear();
                    _operatorController.clear();
                  });
                  _applyFilters();
                },
                child: const Text('Réinitialiser'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateBtn(DateTime? date, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
        child: Row(
          children: [
            const Icon(Icons.calendar_month, size: 14, color: Colors.grey),
            const SizedBox(width: 6),
            Text(date == null ? label : DateFormat('dd/MM/yy').format(date), style: const TextStyle(fontSize: 12)),
          ],
        ),
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
                DropdownMenuItem(value: 'lotNumber', child: Text('Lot')),
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
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WeighingHistoryDetailScreen(session: session, userRole: 'admin'))),
        title: Text('Lot: ${session.lotNumber ?? session.lotId}', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('${session.farmName} • ${session.operator}'),
            if (session.isSuperseded == true) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4)),
                child: const Text(
                  'ANCIENNE PESÉE (remplacée cette semaine)',
                  style: TextStyle(fontSize: 9, color: Colors.black54, fontWeight: FontWeight.bold),
                ),
              ),
            ],
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
