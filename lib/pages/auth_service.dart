import 'package:cloud_firestore/cloud_firestore.dart';

Future<String?> detectRole(String id) async {
  final firestore = FirebaseFirestore.instance;

  if ((await firestore.collection("students").doc(id).get()).exists) {
    return "students";
  }

  if ((await firestore.collection("personalAdvisor").doc(id).get()).exists) {
    return "personalAdvisor";
  }

  if ((await firestore.collection("counsellors").doc(id).get()).exists) {
    return "counsellors";
  }

  if ((await firestore.collection("admins").doc(id).get()).exists) {
    return "admins";
  }

  return null;
}
