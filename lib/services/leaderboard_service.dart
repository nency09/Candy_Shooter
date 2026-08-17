import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

class WeeklyLeaderboardEntry {
  const WeeklyLeaderboardEntry({
    required this.uid,
    required this.name,
    required this.score,
  });

  final String uid;
  final String name;
  final int score;

  factory WeeklyLeaderboardEntry.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return WeeklyLeaderboardEntry(
      uid: snapshot.id,
      name: (data['displayName'] as String?)?.trim().isNotEmpty == true
          ? (data['displayName'] as String).trim()
          : 'Candy Player',
      score: (data['score'] as num?)?.toInt() ?? 0,
    );
  }
}

class LeaderboardService {
  LeaderboardService({FirebaseFirestore? firestore}) : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  bool get _isAvailable => _firestore != null || Firebase.apps.isNotEmpty;

  FirebaseFirestore get _db {
    if (!_isAvailable) throw StateError('Firebase has not been initialized.');
    return _firestore ?? FirebaseFirestore.instance;
  }

  static String currentWeekId([DateTime? value]) {
    final today = value ?? DateTime.now();
    final date = DateTime(today.year, today.month, today.day);
    final monday = date.subtract(
      Duration(days: date.weekday - DateTime.monday),
    );
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${monday.year}-${twoDigits(monday.month)}-${twoDigits(monday.day)}';
  }

  CollectionReference<Map<String, dynamic>> _playersForWeek(String weekId) =>
      _db.collection('weeklyLeaderboards').doc(weekId).collection('players');

  Stream<List<WeeklyLeaderboardEntry>> watchTop({int limit = 20}) {
    if (!_isAvailable) return Stream.value(const <WeeklyLeaderboardEntry>[]);
    return _playersForWeek(currentWeekId())
        .orderBy('score', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(WeeklyLeaderboardEntry.fromSnapshot).toList(),
        );
  }

  Stream<WeeklyLeaderboardEntry?> watchPlayer(String uid) {
    if (!_isAvailable) return Stream.value(null);
    return _playersForWeek(currentWeekId())
        .doc(uid)
        .snapshots()
        .map(
          (snapshot) => snapshot.exists
              ? WeeklyLeaderboardEntry.fromSnapshot(snapshot)
              : null,
        );
  }

  Future<void> submitBestScore({
    required String uid,
    required String displayName,
    required int score,
  }) async {
    if (!_isAvailable || score <= 0) return;
    final player = _playersForWeek(currentWeekId()).doc(uid);
    await _db.runTransaction((transaction) async {
      final existing = await transaction.get(player);
      final previous = (existing.data()?['score'] as num?)?.toInt() ?? 0;
      if (!existing.exists || score > previous) {
        transaction.set(player, {
          'uid': uid,
          'displayName': displayName,
          'score': score,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
  }
}
