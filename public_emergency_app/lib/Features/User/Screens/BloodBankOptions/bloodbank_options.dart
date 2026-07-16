// TODO Implement this library.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class BloodBankOptions extends StatelessWidget {
  const BloodBankOptions({super.key});

  final List<Map<String, String>> bloodBanks = const [
    {
      "name": "Red Crescent Blood Bank",
      "phone": "03001234567",
      "address": "Karachi, Pakistan"
    },
    {
      "name": "Indus Hospital Blood Bank",
      "phone": "03111222333",
      "address": "Karachi, Pakistan"
    },
    {
      "name": "Fatimid Foundation",
      "phone": "03221234567",
      "address": "Karachi, Pakistan"
    },
  ];

  void callNumber(String number) async {
    final Uri url = Uri.parse("tel:$number");
    await launchUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Blood Bank"),
        backgroundColor: const Color(0xFFB91C1C),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: bloodBanks.length,
        itemBuilder: (context, index) {
          final bank = bloodBanks[index];

          return Card(
            child: ListTile(
              leading: const Icon(Icons.bloodtype, color: Colors.red),
              title: Text(bank["name"]!),
              subtitle: Text(bank["address"]!),
              trailing: IconButton(
                icon: const Icon(Icons.call, color: Colors.green),
                onPressed: () => callNumber(bank["phone"]!),
              ),
            ),
          );
        },
      ),
    );
  }
}