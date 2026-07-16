import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:public_emergency_app/Features/User/Screens/FirefighterOptions/firefighter_options.dart';
import 'package:public_emergency_app/Features/User/Screens/HospitalOptions/hospital_options.dart';
import 'package:public_emergency_app/Features/User/Screens/PoliceOptions/police_options.dart';
import 'package:public_emergency_app/Features/User/Screens/PharmacyOptions/pharmacy_options.dart';
import 'package:public_emergency_app/Features/User/Screens/BloodBankOptions/bloodbank_options.dart';
import 'package:public_emergency_app/Features/User/Screens/HelplineOptions/helpline_options.dart';

class GridDashboard extends StatelessWidget {
  final VoidCallback? onItemTap;
  GridDashboard({super.key, this.onItemTap});

  final Items item1 = Items(title: "Police", subtitle: "Emergency Police", event: "", img: "assets/logos/policeman.png");
  final Items item2 = Items(title: "Fire Brigade", subtitle: "Emergency Fire Brigade", event: "", img: "assets/logos/fire-truck.png");
  final Items item3 = Items(title: "Pharmacy", subtitle: "Emergency Pharmacy", event: "", img: "assets/logos/pharmacy.png");
  final Items item4 = Items(title: "Hospitals", subtitle: "Emergency Hospitals", event: "", img: "assets/logos/hospital.png");
  final Items item5 = Items(title: "Blood Bank", subtitle: "Emergency Blood Services", event: "", img: "assets/logos/BloodBank.png");
  final Items item6 = Items(title: "Helpline", subtitle: "Emergency Helpline", event: "", img: "assets/logos/Helpline.png");

  Color getServiceColor(String title) {
    switch (title) {
      case "Police": return const Color(0xFF1E3A8A);
      case "Fire Brigade": return const Color(0xFFDC2626);
      case "Pharmacy": return const Color(0xFF059669);
      case "Hospitals": return const Color(0xFF7C3AED);
      case "Blood Bank": return const Color(0xFFB91C1C);
      case "Helpline": return const Color(0xFF2563EB);
      default: return const Color(0xFF0F4C5C);
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Items> myList = [item1, item2, item3, item4, item5, item6];
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        final isSmallScreen = screenWidth < 360;
        final isLargeScreen = screenWidth > 600;
        final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
        
        // Responsive spacings
        final double crossAxisSpacing = isSmallScreen 
            ? 6.0 
            : isLargeScreen 
                ? 15.0 
                : 10.0;
                
        final double mainAxisSpacing = isSmallScreen 
            ? 6.0 
            : isLargeScreen 
                ? 15.0 
                : 10.0;
                
        final double horizontalPadding = isSmallScreen 
            ? 2.0 
            : isLargeScreen 
                ? 8.0 
                : 4.0;
                
        final double verticalPadding = isSmallScreen 
            ? 4.0 
            : isLargeScreen 
                ? 12.0 
                : 8.0;

        final int rowCount = 3;
        final int colCount = 2;

        final double totalVerticalSpacing = mainAxisSpacing * (rowCount - 1);
        final double totalHorizontalSpacing = crossAxisSpacing * (colCount - 1);

        final double itemHeight = (constraints.maxHeight - (verticalPadding * 2) - totalVerticalSpacing) / rowCount;
        final double itemWidth = (constraints.maxWidth - (horizontalPadding * 2) - totalHorizontalSpacing) / colCount;

        final double aspectRatio = itemWidth / itemHeight;

        // =============================================
        // UNIFORM FONT SIZES FOR ALL ITEMS
        // =============================================
        final double titleFontSize = isSmallScreen 
            ? itemHeight * 0.09 
            : isLargeScreen 
                ? itemHeight * 0.10  // Slightly adjusted
                : itemHeight * 0.095; // Slightly adjusted
        
        final double subtitleFontSize = isSmallScreen 
            ? itemHeight * 0.055 
            : isLargeScreen 
                ? itemHeight * 0.065 
                : itemHeight * 0.06;
        // =============================================

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: aspectRatio,
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding, 
            vertical: verticalPadding
          ),
          crossAxisCount: colCount,
          crossAxisSpacing: crossAxisSpacing,
          mainAxisSpacing: mainAxisSpacing,
          children: myList.map((data) {
            return GestureDetector(
              onTap: () {
                onItemTap?.call();
                switch (data.title) {
                  case "Police": Get.to(() => const PoliceOptions()); break;
                  case "Fire Brigade": Get.to(() => const FireFighterOptions()); break;
                  case "Pharmacy": Get.to(() => const PharmacyOptions()); break;
                  case "Hospitals": Get.to(() => const HospitalOptions()); break;
                  case "Blood Bank": Get.to(() => const BloodBankOptions()); break;
                  case "Helpline": Get.to(() => const HelplineOptions()); break;
                  default: Get.snackbar("Error", "Service not available");
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      getServiceColor(data.title),
                      getServiceColor(data.title).withOpacity(0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
                  boxShadow: [
                    BoxShadow(
                      color: getServiceColor(data.title).withOpacity(0.4),
                      blurRadius: isSmallScreen ? 4 : 8,
                      offset: Offset(0, isSmallScreen ? 2 : 4),
                    ),
                  ],
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: isSmallScreen ? 4.0 : isLargeScreen ? 12.0 : 8.0,
                  vertical: isSmallScreen ? 4.0 : isLargeScreen ? 10.0 : 6.0,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Responsive icon size (UNIFORM for all)
                    SizedBox(
                      height: isSmallScreen 
                          ? itemHeight * 0.35 
                          : isLargeScreen 
                              ? itemHeight * 0.45 
                              : itemHeight * 0.42,
                      width: isSmallScreen 
                          ? itemHeight * 0.35 
                          : isLargeScreen 
                              ? itemHeight * 0.45 
                              : itemHeight * 0.42,
                      child: Image.asset(data.img, fit: BoxFit.contain),
                    ),
                    SizedBox(height: itemHeight * 0.04),
                    
                    // =============================================
                    // TITLE - SAME SIZE FOR ALL 6 GRIDS
                    // =============================================
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 2),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          data.title,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.openSans(
                            textStyle: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                              // USING THE SAME UNIFORM FONT SIZE
                              fontSize: titleFontSize,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // =============================================
                    
                    SizedBox(height: itemHeight * 0.02),
                    
                    // =============================================
                    // SUBTITLE - SAME SIZE FOR ALL 6 GRIDS
                    // =============================================
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 2),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          data.subtitle,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.openSans(
                            textStyle: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              height: 1.2,
                              // USING THE SAME UNIFORM FONT SIZE
                              fontSize: subtitleFontSize,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // =============================================
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class Items {
  String title;
  String subtitle;
  String event;
  String img;
  Items({required this.title, required this.subtitle, required this.event, required this.img});
}