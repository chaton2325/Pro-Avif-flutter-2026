import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import './mongo_service.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  final MongoService _mongoService = MongoService();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isSyncing = false;

  factory SyncService() {
    return _instance;
  }

  SyncService._internal();

  void startObserving() {
    _subscription?.cancel();
    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        _attemptAutoSync();
      }
    });
  }

  Future<void> _attemptAutoSync() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      // Small delay to ensure network is actually stable
      await Future.delayed(const Duration(seconds: 2));
      
      print("Network detected: Attempting auto-sync...");
      int count = await _mongoService.syncOfflineSessions();
      if (count > 0) {
        print("Auto-sync success: $count sessions uploaded.");
      }
    } catch (e) {
      print("Auto-sync failed: $e");
    } finally {
      _isSyncing = false;
    }
  }

  void stopObserving() {
    _subscription?.cancel();
  }
}
