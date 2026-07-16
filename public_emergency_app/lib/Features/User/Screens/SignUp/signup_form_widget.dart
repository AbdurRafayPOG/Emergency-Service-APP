import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../Common Widgets/constants.dart';
import '../../Controllers/signup_controller.dart';
import 'package:flutter/services.dart';

class SignUpFormWidget extends StatefulWidget {
  const SignUpFormWidget({super.key});

  @override
  State<SignUpFormWidget> createState() => _SignUpFormWidgetState();
}

bool isChecked = false;

class _SignUpFormWidgetState extends State<SignUpFormWidget> {
  final controller = Get.put(SignUpController());
  bool _obscurePassword = true; // // eye toggle state

  @override
  Widget build(BuildContext context) {
    final formKey = GlobalKey<FormState>();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: controller.fullName,
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'This field is required';
                if (value.trim().length < 2) return 'Name must be valid';
                return null;
              },
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.person_outline_rounded),
                labelText: "Full Name",
                hintText: "Full Name",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),

            const SizedBox(height: 10),

            TextFormField(
              controller: controller.email,
              enableSuggestions: false,
              autocorrect: false,
              validator: (value) {
                // Check if value contains @ symbol
                if (value == null || !value.contains('@')) {
                  return 'Please enter a valid email address (must contain @)';
                }
                return null;
              },
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.email_outlined),
                labelText: "Email",
                hintText: "Email",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),

            const SizedBox(height: 10),
//Phone number

            TextFormField(
  controller: controller.phoneNo,
  keyboardType: TextInputType.phone,
  inputFormatters: [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(10),
  ],
  validator: (value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }
    
    String cleanNumber = value.trim();

    if (cleanNumber.length != 10) {
      return 'Phone number must be exactly 10 digits';
    }

    if (!cleanNumber.startsWith('3')) {
      return 'Pakistani number must start with 3';
    }

    if (!RegExp(r'^[0-9]+$').hasMatch(cleanNumber)) {
      return 'Only digits allowed';
    }

    return null;
  },
  decoration: InputDecoration(
    prefixIcon: const Icon(Icons.phone),
    labelText: "Phone Number",
    hintText: "3XX YYYYYYY",
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
    helperStyle: const TextStyle(fontSize: 12, color: Colors.grey),
    prefixText: '+92 ',
    prefixStyle: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: Colors.black,
    ),
  ),
),

            const SizedBox(height: 10),

            // Password with eye toggle
TextFormField(
  controller: controller.password,
  obscureText: _obscurePassword,
  enableSuggestions: false,
  autocorrect: false,
  validator: (value) {
    if (value == null || value.trim().isEmpty) return 'This field is required';
    if (value.trim().length < 6) return 'Password must be at least 6 characters';
    return null;
  },
  decoration: InputDecoration(
    prefixIcon: const Icon(Icons.fingerprint),
    labelText: "Password",
    hintText: "Password",
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
    suffixIcon: IconButton(
      icon: Icon(
        _obscurePassword ? Icons.visibility_off : Icons.visibility,
      ),
      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
    ),
  ),
),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Color(color),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) {
                      return StatefulBuilder(
                        builder: (context, setState) {
                          return AlertDialog(
                            title: const Center(child: Text("Terms & Conditions")),
                            insetPadding: const EdgeInsets.symmetric(horizontal: 20),
                            titleTextStyle: TextStyle(
                              color: Color(color),
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.all(Radius.circular(15.0)),
                            ),
                            scrollable: true,
                            content: const Wrap(
                              runAlignment: WrapAlignment.center,
                              runSpacing: 10,
                              children: [
                                Text("User Agreement",
                                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                Text(
                                  "Welcome to Emergency Services. Our app provides a platform for quick response services from police, ambulance, and firefighters in times of emergency.",
                                  style: TextStyle(fontSize: 15, fontFamily: 'Roboto'),
                                ),
                                Text(
                                  "Our app allows you to quickly send out an emergency request with just a few taps, and our responders will be alerted to your location within seconds. As a responder, you can choose your area of expertise and set your availability status. This allows citizens to see which responders are available and respond to emergency requests accordingly. We take your safety seriously. Our app includes a panic button feature, allowing you to quickly alert responders if you're in danger. Additionally, all interactions between responders and citizens are monitored to ensure the highest level of safety. By using our app, you agree to be bound by the following terms and conditions. If you do not agree to these terms and conditions, you may not use our app.",
                                  strutStyle: StrutStyle(fontFamily: 'Roboto', height: 1.5),
                                  style: TextStyle(fontFamily: 'Roboto'),
                                ),
                              ],
                            ),
                            actions: [
                              // Updated actions section with checkbox aligned to far left
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.start,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Checkbox(
                                          activeColor: Color(color),
                                          checkColor: Colors.white,
                                          value: isChecked,
                                          onChanged: (bool? value) {
                                            setState(() => isChecked = value!);
                                          },
                                        ),
                                        const Flexible(
                                          child: Text(
                                            'I agree with the Terms and Conditions',
                                            style: TextStyle(
                                              fontFamily: 'Roboto', 
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Center(
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Color(color),
                                          minimumSize: const Size(200, 45),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                        ),
                                        onPressed: () {
                                          if (!isChecked) {
                                            Get.snackbar(
                                              "Error",
                                              "Please agree to the terms and conditions",
                                              snackPosition: SnackPosition.BOTTOM,
                                              backgroundColor: Colors.red,
                                              colorText: Colors.white,
                                              duration: const Duration(seconds: 3),
                                            );
                                          } else {
                                            Navigator.of(context).pop();
                                            if (formKey.currentState!.validate()) {
// Add leading 0 to phone number before saving
String phoneWithZero = '0${controller.phoneNo.text.trim()}';

SignUpController.instance.signUp(
  controller.fullName.text.trim(),
  controller.email.text.trim(),
  controller.password.text.trim(),
  phoneWithZero, // This will save as "03102650187"
  'User',
);
                                            }
                                          }
                                        },
                                        child: const Text(
                                          "Continue", 
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
                child: Text("Sign Up".toUpperCase()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}