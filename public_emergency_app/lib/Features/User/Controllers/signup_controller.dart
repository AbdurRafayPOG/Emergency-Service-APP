import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:public_emergency_app/Features/User/Controllers/session_controller.dart';
import '../Screens/SignUp/verify_email_page.dart';

class SignUpController extends GetxController {
  static SignUpController get instance => Get.find();

  final email = TextEditingController();
  final password = TextEditingController();
  final fullName = TextEditingController();
  final phoneNo = TextEditingController();

  late DatabaseReference ref;

  @override
  void onInit() {
    super.onInit();
    ref = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://emergencyresponse-0xyvwt-default-rtdb.asia-southeast1.firebasedatabase.app/',
    ).ref('Users'); // // Regular users always go to Users/
  }

  void signUp(String username, String email, String password,
      String phone, String usertype) async {
    try {
      UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      SessionController().userid = userCredential.user!.uid;

      // // Self-registered users always go to Users/ node
// Add leading 0 to phone number before saving
String formattedPhone = phone.startsWith('0') ? phone : '0$phone';

await ref.child(userCredential.user!.uid).set({
  'email': userCredential.user!.email.toString(),
  'UserName': username,
  'Phone': formattedPhone, // This will save as "03102650187"
  'UserType': usertype, // // Always 'User' from signup form
});

      Get.offAll(() => const VerifyEmailPage());
      Get.snackbar('Success', 'Sign Up Successfully');
    } on FirebaseAuthException catch (error) {
      if (error.code == 'email-already-in-use') {
        Get.snackbar('Error', 'Email Already In Use');
      } else if (error.code == 'weak-password') {
        Get.snackbar('Error', 'Password Should Be At Least 6 Characters');
      } else if (error.code == 'invalid-email') {
        Get.snackbar('Error', 'Invalid Email');
      } else if (error.code == 'network-request-failed') {
        Get.snackbar('Error', 'Check Your Internet Connection');
      } else {
        Get.snackbar('Error', error.message ?? error.toString());
      }
    } catch (error) {
      Get.snackbar('Error', error.toString());
      debugPrint(error.toString());
    }
  }
}