import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class Keys {

  static String userId = "";
  static String userName = "";
  
  static String currentUserId = "";
  static String currentUserName = "";
  
  static String responderType = "";
  static String responderName = "";
  static String doctorName = "";
  
  // ✅ Fetch username ONLY from Realtime Database
  static Future<void> initializeFromDatabase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    try {
      final DatabaseReference ref = FirebaseDatabase.instance.ref();
      final snapshot = await ref.child('Users').child(user.uid).get();
      
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        String name = data['UserName']?.toString() ?? 'User';
        
        currentUserId = user.uid;
        currentUserName = name;
        userId = user.uid;
        userName = name;
        print("✅ Keys initialized from Database: $name");
      } else {
        // ✅ ONLY use 'User' as fallback, NOT email
        currentUserId = user.uid;
        currentUserName = 'User';
        userId = user.uid;
        userName = 'User';
        print("⚠️ No UserName in database, using 'User'");
      }
    } catch (e) {
      print("⚠️ Could not fetch from database: $e");
      // ✅ ONLY use 'User' as fallback, NOT email
      currentUserId = user.uid;
      currentUserName = 'User';
      userId = user.uid;
      userName = 'User';
    }
  }
  
  static void setUserInfo(String id, String name) {
    currentUserId = id;
    currentUserName = name;
    userId = id;
    userName = name;
  }
  
  static void setCurrentUser(String id, String name) {
    currentUserId = id;
    currentUserName = name;
    userId = id;
    userName = name;
  }
  
  static void resetForNewCall() {}
}