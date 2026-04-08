import 'package:cloud_firestore/cloud_firestore.dart';

const String manualFoodsCollection = 'manual_foods';

CollectionReference<Map<String, dynamic>> userManualFoodsCollection(
  String userId,
) {
  return FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .collection(manualFoodsCollection);
}
