import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/user.dart';
import '../models/weighing_session.dart';
import '../services/mongo_service.dart';
import '../services/session_storage.dart';
import 'weighing_history_detail_screen.dart';

enum HistorySort { dateDesc, dateAsc, lotNumber, homogeneity }

class UserHistoryScreen extends StatefulWidget {
  final User user;

  const UserHistoryScreen({super.key, required this.user});

  @override
  State<UserHistoryScreen> createState() => _UserHistoryScreenState();
}

class _UserHistoryScreenState extends State<UserHistoryScreen> {
  final MongoService _mongoService = MongoService();
  List<WeighingSession> _allSessions = [];
  List<WeighingSession> _filteredSessions = [];
  bool _isLoading = true;
  
  HistorySort _currentSort = HistorySort.dateDesc;
  String _searchQuery = '';
  bool? _filterSynced; // null: all, true: synced only, false: local only

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    
    try {
      final offline = await SessionStorage.getOfflineSessions();
      
      // Load server data using the paginated endpoint with userId filter
      // Note: We fetch a large enough limit to cover recent history
      final result = await _mongoService.getPaginatedWeighings(limit: 100);
      final List<dynamic> data = result['data'];
      final server = data
          .map((s) => WeighingSession.fromMap(s))
          .where((s) => s.userId == widget.user.id)
          .toList();
      
      if (!mounted) return;
      setState(() {
        _allSessions = [...offline, ...server];
        _applyFiltersAndSort();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _applyFiltersAndSort() {
    List<WeighingSession> filtered = List.from(_allSessions);

    // 1. Search Filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((s) => 
        (s.lotNumber ?? s.lotId).toLowerCase().contains(_searchQuery.toLowerCase()) ||
        s.farmName.toLowerCase().contains(_searchQuery.toLowerCase())
      ).toList();
    }

    // 2. Sync Filter
    if (_filterSynced != null) {
      filtered = filtered.where((s) => s.isSync == _filterSynced).toList();
    }

    // 3. Sorting
    switch (_currentSort) {
      case HistorySort.dateDesc:
        filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        break;
      case HistorySort.dateAsc:
        filtered.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        break;
      case HistorySort.lotNumber:
        filtered.sort((a, b) => a.lotId.compareTo(b.lotId));
        break;
      case HistorySort.homogeneity:
        filtered.sort((a, b) => b.homogeneity.compareTo(a.homogeneity));
        break;
    }

    setState(() {
      _filteredSessions = filtered;
    });
  }

  double _calculateHomogeneity(WeighingSession s) {
    return s.homogeneity;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('MON HISTORIQUE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loadHistory),
        ],
      ),
      body: Column(
        children: [
          _buildSearchAndFilterBar(),
          _buildSortChips(),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Colors.orange))
              : _filteredSessions.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _filteredSessions.length,
                    itemBuilder: (context, index) => _buildEnhancedSessionCard(_filteredSessions[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilterBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: Theme.of(context).primaryColor.withValues(alpha: 0.05),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (val) {
                _searchQuery = val;
                _applyFiltersAndSort();
              },
              decoration: InputDecoration(
                hintText: 'Rechercher un lot ou bâtiment...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildFilterMenu(),
        ],
      ),
    );
  }

  Widget _buildFilterMenu() {
    return PopupMenuButton<bool?>(
      icon: Icon(Icons.filter_list, color: _filterSynced == null ? Colors.grey : Colors.orange),
      onSelected: (val) {
        setState(() => _filterSynced = val);
        _applyFiltersAndSort();
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: null, child: Text('Tous les statuts')),
        const PopupMenuItem(value: true, child: Text('Synchronisés uniquement')),
        const PopupMenuItem(value: false, child: Text('Local (à synchroniser)')),
      ],
    );
  }

  Widget _buildSortChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _sortChip('Plus récent', HistorySort.dateDesc),
          _sortChip('Plus ancien', HistorySort.dateAsc),
          _sortChip('Par Lot', HistorySort.lotNumber),
          _sortChip('Homogénéité', HistorySort.homogeneity),
        ],
      ),
    );
  }

  Widget _sortChip(String label, HistorySort value) {
    bool selected = _currentSort == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : Colors.black87)),
        selected: selected,
        selectedColor: Colors.orange,
        backgroundColor: Colors.white,
        onSelected: (bool s) {
          if (s) {
            setState(() => _currentSort = value);
            _applyFiltersAndSort();
          }
        },
      ),
    );
  }

  Widget _buildEnhancedSessionCard(WeighingSession session) {
    final double homogeneity = _calculateHomogeneity(session);
    final String dateStr = DateFormat('dd MMM yyyy, HH:mm').format(session.timestamp);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context, 
          MaterialPageRoute(builder: (_) => WeighingHistoryDetailScreen(session: session, userRole: 'user'))
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: session.isSync ? Colors.green.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      session.isSync ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                      color: session.isSync ? Colors.green : Colors.orange,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                'LOT: ${session.lotNumber ?? session.lotId}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${homogeneity.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: homogeneity >= 80 ? Colors.green : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${session.farmName} • ${session.roomName}${session.sex != null ? ' • ${session.sex}' : ''}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.numbers, size: 14, color: Colors.grey[400]),
                                const SizedBox(width: 4),
                                Text('${session.weights.length} sujets', style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.calendar_today, size: 14, color: Colors.grey[400]),
                                const SizedBox(width: 4),
                                Text(dateStr, style: const TextStyle(fontSize: 11)),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? 'Aucune pesée enregistrée' : 'Aucun résultat pour cette recherche',
            style: const TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
