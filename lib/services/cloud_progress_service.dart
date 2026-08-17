import 'package:cloud_firestore/cloud_firestore.dart';

class CloudProgressService {
  CloudProgressService(this.uid, {FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _db;
  DocumentReference<Map<String, dynamic>> get _profile =>
      _db.collection('users').doc(uid);

  Future<Map<String, Object>?> load() async {
    final snapshot = await _profile.get();
    if (!snapshot.exists) return null;
    return Map<String, Object>.from(snapshot.data()!);
  }

  Future<void> save(Map<String, Object> progress) => _profile.set({
    ...progress,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  Future<void> createProfile({required String name, required String email}) =>
      _profile.set({
        'displayName': name,
        'email': email,
        'currentLevel': 1,
        'coins': 0,
        'stars': <int>[],
        'scores': <int>[],
        'boosters': <String, int>{},
        'claimedRewards': <int>[],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
}
