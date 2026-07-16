import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:public_emergency_app/Common%20Widgets/constants.dart';

class ResponderHistoryScreen extends StatefulWidget {
  const ResponderHistoryScreen({Key? key}) : super(key: key);

  @override
  State<ResponderHistoryScreen> createState() => _ResponderHistoryScreenState();
}

class _ResponderHistoryScreenState extends State<ResponderHistoryScreen> {
  late DatabaseReference sosDoneRef;
  late DatabaseReference assignedRef;
  final String firebaseDatabaseUrl =
      'https://emergencyresponse-0xyvwt-default-rtdb.asia-southeast1.firebasedatabase.app';
  
  // Filter state
  String _selectedStatusFilter = 'All';
  String _selectedTypeFilter = 'All';
  String _selectedTimeFilter = 'Latest';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  
  List<Map<String, dynamic>> _allHistoryEntries = [];
  List<Map<String, dynamic>> _filteredHistoryEntries = [];
  Map<String, Map<String, dynamic>> _userCache = {};
  Map<String, Map<String, dynamic>> _responderCache = {};
  bool _isLoading = true;
  String _errorMessage = '';
  Set<String> _expandedCards = {};

  @override
  void initState() {
    super.initState();
    _initializeDatabase();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeDatabase() async {
    try {
      await Firebase.initializeApp();
      final db = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: firebaseDatabaseUrl,
      );
      sosDoneRef = db.ref().child('SOS_Done');
      assignedRef = db.ref().child('assigned');
      
      await _loadAllDataAtOnce();
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error initializing database: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading data';
      });
    }
  }

  String _normalizeType(String? type) {
    if (type == null) return '';
    final normalized = type.trim().toLowerCase();
    if (normalized == 'firefighter' || normalized == 'fire fighter' || normalized == 'fire-fighter') {
      return 'Firefighter';
    }
    if (normalized == 'police') {
      return 'Police';
    }
    return type;
  }

  String _formatDateTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year;
    return '$hour:$minute:$second $day/$month/$year';
  }

  // ============================================================
  // ✅ LOAD DATA WITH ACTUAL STRUCTURE
  // ============================================================
  Future<void> _loadAllDataAtOnce() async {
    try {
      print('=== LOADING RESPONDER HISTORY ===');
      
      final usersRef = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: firebaseDatabaseUrl,
      ).ref('Users');
      
      final respondersRef = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: firebaseDatabaseUrl,
      ).ref('Responders');

      final results = await Future.wait([
        sosDoneRef.once(),
        assignedRef.once(),
        usersRef.once(),
        respondersRef.once(),
      ]);

      final sosDoneSnapshot = results[0];
      final assignedSnapshot = results[1];
      final usersSnapshot = results[2];
      final respondersSnapshot = results[3];

      // Build user cache
      if (usersSnapshot.snapshot.value != null) {
        final usersData = Map<dynamic, dynamic>.from(usersSnapshot.snapshot.value as Map);
        for (var userEntry in usersData.entries) {
          final userId = userEntry.key;
          final userData = Map<dynamic, dynamic>.from(userEntry.value);
          _userCache[userId] = {
            'name': userData['UserName']?.toString() ?? 'Unknown User',
            'phone': userData['Phone']?.toString() ?? '',
            'email': userData['email']?.toString() ?? '',
            'address': userData['address']?.toString() ?? '',
          };
        }
      }

      // Build responder cache
      if (respondersSnapshot.snapshot.value != null) {
        final respondersData = Map<dynamic, dynamic>.from(respondersSnapshot.snapshot.value as Map);
        for (var responderEntry in respondersData.entries) {
          final responderId = responderEntry.key;
          final responderData = Map<dynamic, dynamic>.from(responderEntry.value);
          final rawType = responderData['UserType']?.toString() ?? 'Unknown';
          _responderCache[responderId] = {
            'name': responderData['UserName']?.toString() ?? 'Unknown',
            'type': _normalizeType(rawType),
            'phone': responderData['Phone']?.toString() ?? '',
            'email': responderData['email']?.toString() ?? '',
          };
        }
      }

      final List<Map<String, dynamic>> entries = [];

      // ============================================================
      // 1. ✅ PROCESS COMPLETED EMERGENCIES (SOS_Done)
      // ============================================================
      if (sosDoneSnapshot.snapshot.value != null) {
        print('Processing COMPLETED emergencies from SOS_Done...');
        final sosDoneData = Map<dynamic, dynamic>.from(sosDoneSnapshot.snapshot.value as Map);

        for (var entry in sosDoneData.entries) {
          final emergencyId = entry.key;
          final emergencyData = Map<dynamic, dynamic>.from(entry.value);
          
          final userInfo = emergencyData['userInfo'] ?? {};
          final userId = userInfo['uid']?.toString() ?? '';
          final userDetails = _userCache[userId] ?? {
            'name': userInfo['name']?.toString() ?? 'Unknown User',
            'phone': userInfo['phone']?.toString() ?? '',
            'email': userInfo['email']?.toString() ?? '',
            'address': userInfo['address']?.toString() ?? '',
          };

          final responderInfo = emergencyData['completedBy'] ?? {};
          final responderId = responderInfo['uid']?.toString() ?? '';
          final responderDetails = _responderCache[responderId] ?? {
            'name': responderInfo['name']?.toString() ?? 'Unknown',
            'type': _normalizeType(responderInfo['type']?.toString()),
            'phone': responderInfo['phone']?.toString() ?? '',
            'email': responderInfo['email']?.toString() ?? '',
          };

          final emergencyDataFields = emergencyData['emergencyData'] ?? {};
          
          String userAddress = emergencyDataFields['userAddress']?.toString() ?? '';
          if (userAddress.isEmpty || userAddress == 'No Address') {
            userAddress = userDetails['address'] ?? 'No Address';
          }

          String sosTime = 'Unknown time';
          if (emergencyData['sosTimeFormatted'] != null) {
            sosTime = emergencyData['sosTimeFormatted'].toString();
          } else if (emergencyData['sosTime'] != null) {
            try {
              final sosTimeMs = emergencyData['sosTime'] as int;
              final sosDateTime = DateTime.fromMillisecondsSinceEpoch(sosTimeMs);
              sosTime = _formatDateTime(sosDateTime);
            } catch (e) {
              sosTime = 'Unknown time';
            }
          }

          // Format completion time
          String formattedCompletionTime = 'In Progress';
          if (emergencyData['completedAt'] != null) {
            try {
              String completionStr = emergencyData['completedAt'].toString();
              if (completionStr.contains(' ') && completionStr.contains(':')) {
                formattedCompletionTime = completionStr;
              } else {
                DateTime? completionDateTime;
                try {
                  completionDateTime = DateTime.parse(completionStr);
                } catch (e) {
                  final completionMs = int.tryParse(completionStr);
                  if (completionMs != null) {
                    completionDateTime = DateTime.fromMillisecondsSinceEpoch(completionMs);
                  }
                }
                if (completionDateTime != null) {
                  formattedCompletionTime = _formatDateTime(completionDateTime);
                } else {
                  formattedCompletionTime = completionStr;
                }
              }
            } catch (e) {
              formattedCompletionTime = emergencyData['completedAt']?.toString() ?? 'In Progress';
            }
          }

          String responseTime = emergencyData['responseTime']?.toString() ?? 'N/A';

          entries.add({
            'emergencyId': emergencyId,
            'responderId': responderId,
            'responderName': responderDetails['name'] ?? 'Unknown',
            'responderType': responderDetails['type'] ?? 'Unknown',
            'responderPhone': responderDetails['phone'] ?? '',
            'responderEmail': responderDetails['email'] ?? '',
            'userName': userDetails['name'] ?? 'Unknown User',
            'userId': userId,
            'userPhone': userDetails['phone'] ?? '',
            'userEmail': userDetails['email'] ?? '',
            'userAddress': userAddress,
            'userLat': emergencyDataFields['userLat']?.toString() ?? '0',
            'userLong': emergencyDataFields['userLong']?.toString() ?? '0',
            'time': sosTime,
            'assignedAt': emergencyData['assignedAt']?.toString() ?? '',
            'completedAt': formattedCompletionTime,
            'distance': emergencyData['distance']?.toString() ?? '0 km',
            'responseTime': responseTime,
            'description': emergencyDataFields['description']?.toString() ?? '',
            'status': 'Completed',
            'isCompleted': true,
          });
        }
      }

      // ============================================================
      // 2. ✅ PROCESS ACTIVE EMERGENCIES (assigned)
      // ============================================================
      if (assignedSnapshot.snapshot.value != null) {
        print('Processing ACTIVE emergencies from assigned...');
        final assignedData = Map<dynamic, dynamic>.from(assignedSnapshot.snapshot.value as Map);

        for (var responderEntry in assignedData.entries) {
          final responderId = responderEntry.key;
          final responderData = Map<dynamic, dynamic>.from(responderEntry.value);

          for (var emergencyEntry in responderData.entries) {
            final emergencyData = Map<dynamic, dynamic>.from(emergencyEntry.value);
            
            if (emergencyData['status']?.toString() == 'completed') {
              continue;
            }

            final userId = emergencyData['userID']?.toString() ?? '';
            final userDetails = _userCache[userId] ?? {
              'name': emergencyData['userName']?.toString() ?? 'Unknown User',
              'phone': '',
              'email': emergencyData['userEmail']?.toString() ?? '',
              'address': emergencyData['userAddress']?.toString() ?? 'No Address',
            };

            final responderDetails = _responderCache[responderId] ?? {
              'name': emergencyData['responderName']?.toString() ?? 'Unknown',
              'type': _normalizeType(emergencyData['responderType']?.toString()),
              'phone': emergencyData['responderPhone']?.toString() ?? '',
              'email': '',
            };

            String userAddress = emergencyData['userAddress']?.toString() ?? '';
            if (userAddress.isEmpty || userAddress == 'No Address') {
              userAddress = userDetails['address'] ?? 'No Address';
            }

            String sosTime = 'Unknown time';
            if (emergencyData['sosTime'] != null) {
              try {
                final sosTimeMs = emergencyData['sosTime'] as int;
                final sosDateTime = DateTime.fromMillisecondsSinceEpoch(sosTimeMs);
                sosTime = _formatDateTime(sosDateTime);
              } catch (e) {
                sosTime = 'Unknown time';
              }
            }

            entries.add({
              'emergencyId': emergencyEntry.key,
              'responderId': responderId,
              'responderName': responderDetails['name'] ?? 'Unknown',
              'responderType': responderDetails['type'] ?? 'Unknown',
              'responderPhone': responderDetails['phone'] ?? '',
              'responderEmail': responderDetails['email'] ?? '',
              'userName': userDetails['name'] ?? 'Unknown User',
              'userId': userId,
              'userPhone': userDetails['phone'] ?? '',
              'userEmail': userDetails['email'] ?? '',
              'userAddress': userAddress,
              'userLat': emergencyData['userLat']?.toString() ?? '0',
              'userLong': emergencyData['userLong']?.toString() ?? '0',
              'time': sosTime,
              'assignedAt': emergencyData['assignedAt']?.toString() ?? '',
              'completedAt': '',
              'distance': 'N/A',
              'responseTime': 'N/A',
              'description': '',
              'status': 'Active',
              'isCompleted': false,
            });
          }
        }
      }

      print('Total responder history entries found: ${entries.length}');

      setState(() {
        _allHistoryEntries = entries;
        _applyFilters();
        if (entries.isEmpty) {
          _errorMessage = 'No responder history found';
        }
      });
    } catch (e) {
      print('Error loading responder history: $e');
      setState(() {
        _errorMessage = 'Error loading responder history: $e';
      });
    }
  }

  // ============================================================
  // ✅ APPLY FILTERS
  // ============================================================
  void _applyFilters() {
    List<Map<String, dynamic>> filtered = List.from(_allHistoryEntries);
    
    // Filter by Status (Active / Completed)
    if (_selectedStatusFilter == 'Active') {
      filtered = filtered.where((entry) => entry['isCompleted'] == false).toList();
    } else if (_selectedStatusFilter == 'Completed') {
      filtered = filtered.where((entry) => entry['isCompleted'] == true).toList();
    }
    
    // Filter by Type (All / Police / Firefighter)
    if (_selectedTypeFilter != 'All') {
      filtered = filtered.where((entry) {
        final responderType = entry['responderType']?.toString() ?? '';
        final normalizedType = _normalizeType(responderType);
        return normalizedType == _selectedTypeFilter;
      }).toList();
    }
    
    // Filter by Search Query - search by user name, responder name, user ID, responder ID, emergency ID
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase().trim();
      filtered = filtered.where((entry) {
        final userName = entry['userName']?.toString().toLowerCase() ?? '';
        final responderName = entry['responderName']?.toString().toLowerCase() ?? '';
        final userId = entry['userId']?.toString().toLowerCase() ?? '';
        final responderId = entry['responderId']?.toString().toLowerCase() ?? '';
        final emergencyId = entry['emergencyId']?.toString().toLowerCase() ?? '';
        
        return userName.contains(query) ||
               responderName.contains(query) ||
               userId.contains(query) ||
               responderId.contains(query) ||
               emergencyId.contains(query);
      }).toList();
    }
    
    // Apply time-based filter
    filtered = _applyTimeFilter(filtered);
    
    // Apply sort order
    if (_selectedTimeFilter == 'Latest' || _selectedTimeFilter == 'Today' || 
        _selectedTimeFilter == 'Week' || _selectedTimeFilter == 'Month' || _selectedTimeFilter == 'Year') {
      filtered.sort((a, b) {
        final aTime = a['isCompleted'] == true ? a['completedAt']?.toString() ?? '' : a['assignedAt']?.toString() ?? '';
        final bTime = b['isCompleted'] == true ? b['completedAt']?.toString() ?? '' : b['assignedAt']?.toString() ?? '';
        return bTime.compareTo(aTime);
      });
    } else if (_selectedTimeFilter == 'Oldest') {
      filtered.sort((a, b) {
        final aTime = a['isCompleted'] == true ? a['completedAt']?.toString() ?? '' : a['assignedAt']?.toString() ?? '';
        final bTime = b['isCompleted'] == true ? b['completedAt']?.toString() ?? '' : b['assignedAt']?.toString() ?? '';
        return aTime.compareTo(bTime);
      });
    }
    
    setState(() {
      _filteredHistoryEntries = filtered;
    });
  }

  // ✅ Apply time filter
  List<Map<String, dynamic>> _applyTimeFilter(List<Map<String, dynamic>> entries) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    if (_selectedTimeFilter == 'Latest' || _selectedTimeFilter == 'Oldest') {
      return entries;
    }
    
    return entries.where((entry) {
      String dateString;
      if (entry['isCompleted'] == true) {
        dateString = entry['completedAt']?.toString() ?? '';
      } else {
        dateString = entry['assignedAt']?.toString() ?? '';
      }
      
      if (dateString.isEmpty) return false;
      
      try {
        // Try to parse formatted date first
        DateTime? date;
        if (dateString.contains(' ') && dateString.contains(':')) {
          final parts = dateString.split(' ');
          if (parts.length == 2) {
            final dateParts = parts[1].split('/');
            if (dateParts.length == 3) {
              final day = int.parse(dateParts[0]);
              final month = int.parse(dateParts[1]);
              final year = int.parse(dateParts[2]);
              final timeParts = parts[0].split(':');
              if (timeParts.length == 3) {
                final hour = int.parse(timeParts[0]);
                final minute = int.parse(timeParts[1]);
                final second = int.parse(timeParts[2]);
                date = DateTime(year, month, day, hour, minute, second);
              }
            }
          }
        } else {
          date = DateTime.parse(dateString);
        }
        
        if (date == null) return false;
        
        switch (_selectedTimeFilter) {
          case 'Today':
            final dateDay = DateTime(date.year, date.month, date.day);
            return dateDay.isAtSameMomentAs(today);
            
          case 'Week':
            final weekAgo = today.subtract(const Duration(days: 7));
            return date.isAfter(weekAgo) && date.isBefore(now);
            
          case 'Month':
            return date.year == now.year && date.month == now.month;
            
          case 'Year':
            return date.year == now.year;
            
          default:
            return true;
        }
      } catch (e) {
        return false;
      }
    }).toList();
  }

  // ============================================================
  // ✅ HANDLE SEARCH
  // ============================================================
  void _handleSearch(String query) {
    setState(() {
      _searchQuery = query;
      _applyFilters();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _handleSearch('');
  }

  // ============================================================
  // ✅ HANDLE FILTER CLICK
  // ============================================================
  void _handleFilterClick(String filterType, bool isStatus) {
    setState(() {
      if (isStatus) {
        _selectedStatusFilter = filterType;
      } else {
        _selectedTypeFilter = filterType;
      }
      _applyFilters();
    });
  }

  void _handleTimeFilterClick(String filter) {
    setState(() {
      _selectedTimeFilter = filter;
      _applyFilters();
    });
  }

  String _getRelativeTime(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'Unknown';
    try {
      DateTime? date;
      
      if (dateString.contains(' ') && dateString.contains(':')) {
        final parts = dateString.split(' ');
        if (parts.length == 2) {
          final dateParts = parts[1].split('/');
          if (dateParts.length == 3) {
            final day = int.parse(dateParts[0]);
            final month = int.parse(dateParts[1]);
            final year = int.parse(dateParts[2]);
            final timeParts = parts[0].split(':');
            if (timeParts.length == 3) {
              final hour = int.parse(timeParts[0]);
              final minute = int.parse(timeParts[1]);
              final second = int.parse(timeParts[2]);
              date = DateTime(year, month, day, hour, minute, second);
            }
          }
        }
      } else {
        date = DateTime.parse(dateString);
      }
      
      if (date != null) {
        final now = DateTime.now();
        final difference = now.difference(date);
        
        if (difference.inDays > 0) {
          return '${difference.inDays}d ago';
        } else if (difference.inHours > 0) {
          return '${difference.inHours}h ago';
        } else if (difference.inMinutes > 0) {
          return '${difference.inMinutes}m ago';
        } else {
          return '${difference.inSeconds}s ago';
        }
      }
      return dateString;
    } catch (e) {
      return dateString;
    }
  }

  void _toggleExpand(String key) {
    setState(() {
      if (_expandedCards.contains(key)) {
        _expandedCards.remove(key);
      } else {
        _expandedCards.add(key);
      }
    });
  }

  // ============================================================
  // ✅ COPY TO CLIPBOARD
  // ============================================================
  Future<void> _copyToClipboard(String text, String label) async {
    if (text.isEmpty || text == 'N/A') {
      Get.snackbar(
        'Error',
        'No $label available to copy',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
      );
      return;
    }
    
    try {
      await Clipboard.setData(ClipboardData(text: text));
      Get.rawSnackbar(
        message: 'Copied!',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.black.withOpacity(0.8),
        duration: const Duration(milliseconds: 2000),
        margin: const EdgeInsets.symmetric(horizontal: 120, vertical: 40),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        borderRadius: 10,
        shouldIconPulse: false,
        isDismissible: true,
        forwardAnimationCurve: Curves.easeOut,
        reverseAnimationCurve: Curves.easeIn,
        animationDuration: const Duration(milliseconds: 300),
        snackStyle: SnackStyle.FLOATING,
        messageText: const Center(
          child: Text(
            'Copied!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to copy',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
      );
    }
  }

  // ============================================================
  // ✅ TIME FILTER WIDGET - Shorter and compact
  // ============================================================
  Widget _buildTimeFilterWidget() {
    final timeFilters = [
      {'label': 'Latest', 'icon': Icons.arrow_downward},
      {'label': 'Oldest', 'icon': Icons.arrow_upward},
      {'label': 'Today', 'icon': Icons.today},
      {'label': 'Week', 'icon': Icons.weekend},
      {'label': 'Month', 'icon': Icons.calendar_month},
      {'label': 'Year', 'icon': Icons.calendar_today},
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SizedBox(
        height: 32,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: timeFilters.length,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          itemBuilder: (context, index) {
            final filter = timeFilters[index];
            final label = filter['label'] as String;
            final icon = filter['icon'] as IconData;
            final isSelected = _selectedTimeFilter == label;
            
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _buildTimeFilterChip(
                label: label,
                filterType: label,
                icon: icon,
                isSelected: isSelected,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTimeFilterChip({
    required String label,
    required String filterType,
    required IconData icon,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () {
        _handleTimeFilterClick(filterType);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF0F4C5C),
                    const Color(0xFF0F4C5C).withOpacity(0.8),
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(14),
          color: isSelected ? null : Colors.grey.shade50,
          border: Border.all(
            color: isSelected ? const Color(0xFF0F4C5C) : Colors.grey.shade200,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey.shade600,
              size: 12,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey.shade700,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
// ============================================================
// ✅ FILTER WIDGET - Fixed height and layout
// ============================================================
Widget _buildFilterWidget() {
  final int totalActive = _allHistoryEntries.where((entry) => entry['isCompleted'] == false).length;
  final int totalCompleted = _allHistoryEntries.where((entry) => entry['isCompleted'] == true).length;
  final int totalAll = _allHistoryEntries.length;
  
  final int policeCount = _allHistoryEntries.where((entry) {
    final responderType = entry['responderType']?.toString() ?? '';
    final normalizedType = _normalizeType(responderType);
    return normalizedType == 'Police';
  }).length;
  
  final int firefighterCount = _allHistoryEntries.where((entry) {
    final responderType = entry['responderType']?.toString() ?? '';
    final normalizedType = _normalizeType(responderType);
    return normalizedType == 'Firefighter';
  }).length;

  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withOpacity(0.15),
          spreadRadius: 1,
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Row 1: Status Filters (All | Active | Completed)
        Row(
          children: [
            Expanded(
              child: _buildFilterChip(
                label: 'All',
                filterType: 'All',
                icon: Icons.list_alt,
                count: totalAll,
                isSelected: _selectedStatusFilter == 'All',
                isStatus: true,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _buildFilterChip(
                label: 'Active',
                filterType: 'Active',
                icon: Icons.pending_actions,
                count: totalActive,
                isSelected: _selectedStatusFilter == 'Active',
                isStatus: true,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _buildFilterChip(
                label: 'Completed',
                filterType: 'Completed',
                icon: Icons.check_circle,
                count: totalCompleted,
                isSelected: _selectedStatusFilter == 'Completed',
                isStatus: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Row 2: Type Filters (Police | Firefighter) - NO "All" here
        Row(
          children: [
            Expanded(
              child: _buildFilterChip(
                label: 'Police',
                filterType: 'Police',
                icon: Icons.local_police,
                count: policeCount,
                isSelected: _selectedTypeFilter == 'Police',
                isStatus: false,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _buildFilterChip(
                label: 'Firefighter',
                filterType: 'Firefighter',
                icon: Icons.fire_truck,
                count: firefighterCount,
                isSelected: _selectedTypeFilter == 'Firefighter',
                isStatus: false,
              ),
            ),
            // ✅ REMOVED the third "All" chip from here
          ],
        ),
      ],
    ),
  );
}

  Widget _buildFilterChip({
    required String label,
    required String filterType,
    required IconData icon,
    required int count,
    required bool isSelected,
    required bool isStatus,
  }) {
    return GestureDetector(
      onTap: () {
        _handleFilterClick(filterType, isStatus);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF0F4C5C),
                    const Color(0xFF0F4C5C).withOpacity(0.8),
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(8),
          color: isSelected ? null : Colors.grey.shade50,
          border: Border.all(
            color: isSelected ? const Color(0xFF0F4C5C) : Colors.grey.shade200,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey.shade600,
              size: 10,
            ),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey.shade700,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 9,
                ),
                overflow: TextOverflow.visible,
                softWrap: false,
              ),
            ),
            const SizedBox(width: 2),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 1,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withOpacity(0.2)
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey.shade600,
                  fontWeight: FontWeight.bold,
                  fontSize: 8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ✅ HELPER WIDGET - Two Column Info Row
  // ============================================================
  Widget _buildTwoColumnInfoRow({
    required String label,
    required String value,
    bool isCopyable = false,
    String copyValue = '',
    String copyLabel = '',
    bool isAddress = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value.isEmpty ? 'Not provided' : value,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    maxLines: isAddress ? null : 1,
                    overflow: isAddress ? TextOverflow.visible : TextOverflow.ellipsis,
                  ),
                ),
                if (isCopyable && value.isNotEmpty && value != 'N/A' && value != 'Not provided')
                  GestureDetector(
                    onTap: () => _copyToClipboard(copyValue.isNotEmpty ? copyValue : value, copyLabel.isNotEmpty ? copyLabel : label),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.copy,
                        color: Colors.white.withOpacity(0.4),
                        size: 14,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BUILD METHOD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F4C5C),
        centerTitle: true,
        automaticallyImplyLeading: false,
        toolbarHeight: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(Get.height * 0.16),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 0),
                      child: Image.asset(
                        'assets/logos/emergencyAppLogo.png',
                        height: Get.height * 0.07,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Responder History',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
              Positioned(
                left: 12,
                top: 6,
                child: GestureDetector(
                  onTap: () => Get.back(),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white,
                          Colors.white,
                        ],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.6),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: const Color(0xFF0F4C5C),
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0F4C5C)),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Loading responder history...',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // ✅ SEARCH BAR WITH CLEAR BUTTON - Slightly shorter
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _handleSearch,
                      decoration: InputDecoration(
                        hintText: 'Search by User, Responder, ID...',
                        hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 12,
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: Colors.grey,
                          size: 20,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.grey,
                                  size: 20,
                                ),
                                onPressed: _clearSearch,
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                ),
                
                // ✅ FILTER WIDGET
                _buildFilterWidget(),
                
                // ✅ TIME FILTER WIDGET - Now shorter
                _buildTimeFilterWidget(),
                
                if (_searchQuery.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_filteredHistoryEntries.length} result${_filteredHistoryEntries.length != 1 ? 's' : ''} found',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                
                Expanded(
                  child: _filteredHistoryEntries.isEmpty
                      ? SingleChildScrollView(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(height: 40),
                                Icon(
                                  _searchQuery.isNotEmpty
                                      ? Icons.search_off_rounded
                                      : Icons.person_search_rounded,
                                  size: 70,
                                  color: Colors.grey.shade300,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? 'No results found'
                                      : 'No responder history found',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                                if (_searchQuery.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 24),
                                    child: Text(
                                      'Try searching by User name, Responder name, User ID, Responder ID, or Emergency ID',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 40),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          itemCount: _filteredHistoryEntries.length,
                          itemBuilder: (context, index) {
                            final entry = _filteredHistoryEntries[index];
                            return _buildHistoryCard(entry);
                          },
                        ),
                ),
              ],
            ),
    );
  }

 // ============================================================
// ✅ EXPANDABLE HISTORY CARD
// ============================================================
Widget _buildHistoryCard(Map<String, dynamic> entry) {
  final isCompleted = entry['isCompleted'] ?? false;
  final responderName = entry['responderName'] ?? 'Unknown';
  final responderType = _normalizeType(entry['responderType']?.toString());
  final responderPhone = entry['responderPhone'] ?? '';
  final responderEmail = entry['responderEmail'] ?? '';
  final responderId = entry['responderId'] ?? 'N/A';
  final userName = entry['userName'] ?? 'Unknown User';
  final userId = entry['userId'] ?? 'N/A';
  final userPhone = entry['userPhone'] ?? '';
  final userEmail = entry['userEmail'] ?? '';
  final userAddress = entry['userAddress'] ?? 'No Address';
  final emergencyId = entry['emergencyId'] ?? 'N/A';
  final time = entry['time'] ?? '';
  final completedAt = entry['completedAt'] ?? '';
  final assignedAt = entry['assignedAt'] ?? '';
  final distance = entry['distance'] ?? '0 km';
  final responseTime = entry['responseTime'] ?? 'N/A';
  final description = entry['description'] ?? '';
  final status = entry['status'] ?? 'Active';
  
  final String cardKey = entry['emergencyId'] ?? DateTime.now().toString();
  final bool isExpanded = _expandedCards.contains(cardKey);
  
  // Colors based on responder type
  Color primaryColor;
  Color accentColor;
  
  if (responderType == 'Police') {
    primaryColor = const Color(0xFF0F4C5C);
    accentColor = const Color(0xFF1A7A8C);
  } else if (responderType == 'Firefighter') {
    primaryColor = const Color(0xFF8B4513);
    accentColor = const Color(0xFFCC5500);
  } else {
    primaryColor = const Color(0xFF0F4C5C);
    accentColor = const Color(0xFF1A7A8C);
  }

  // ============================================================
  // ✅ CALCULATE DURATION BETWEEN SOS TIME AND COMPLETION TIME
  // ============================================================
  String _getDurationBetweenTimes(String sosTimeStr, String completedAtStr) {
    if (sosTimeStr.isEmpty || completedAtStr.isEmpty || sosTimeStr == 'Unknown time') {
      return 'N/A';
    }
    
    try {
      DateTime? sosDateTime;
      DateTime? completedDateTime;
      
      // Parse SOS Time (format: "23:25:17 14/07/2026")
      if (sosTimeStr.contains(' ') && sosTimeStr.contains(':')) {
        final sosParts = sosTimeStr.split(' ');
        if (sosParts.length == 2) {
          final sosDateParts = sosParts[1].split('/');
          final sosTimeParts = sosParts[0].split(':');
          if (sosDateParts.length == 3 && sosTimeParts.length == 3) {
            sosDateTime = DateTime(
              int.parse(sosDateParts[2]),
              int.parse(sosDateParts[1]),
              int.parse(sosDateParts[0]),
              int.parse(sosTimeParts[0]),
              int.parse(sosTimeParts[1]),
              int.parse(sosTimeParts[2]),
            );
          }
        }
      }
      
      // Parse Completion Time (format: "23:29:25 14/07/2026")
      if (completedAtStr.contains(' ') && completedAtStr.contains(':')) {
        final compParts = completedAtStr.split(' ');
        if (compParts.length == 2) {
          final compDateParts = compParts[1].split('/');
          final compTimeParts = compParts[0].split(':');
          if (compDateParts.length == 3 && compTimeParts.length == 3) {
            completedDateTime = DateTime(
              int.parse(compDateParts[2]),
              int.parse(compDateParts[1]),
              int.parse(compDateParts[0]),
              int.parse(compTimeParts[0]),
              int.parse(compTimeParts[1]),
              int.parse(compTimeParts[2]),
            );
          }
        }
      }
      
      if (sosDateTime != null && completedDateTime != null) {
        final difference = completedDateTime.difference(sosDateTime);
        
        if (difference.inDays > 0) {
          return '${difference.inDays}d ${difference.inHours % 24}h ${difference.inMinutes % 60}m';
        } else if (difference.inHours > 0) {
          return '${difference.inHours}h ${difference.inMinutes % 60}m';
        } else if (difference.inMinutes > 0) {
          return '${difference.inMinutes}m ${difference.inSeconds % 60}s';
        } else {
          return '${difference.inSeconds}s';
        }
      }
      return 'N/A';
    } catch (e) {
      return 'N/A';
    }
  }

  String durationText = _getDurationBetweenTimes(time, completedAt);

  return GestureDetector(
    onTap: () => _toggleExpand(cardKey),
    child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primaryColor,
            accentColor,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ============================================================
            // COLLAPSED VIEW
            // ============================================================
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isCompleted
                          ? [Colors.green.shade400, Colors.green.shade600]
                          : [Colors.orange.shade400, Colors.orange.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isCompleted ? Icons.check_circle : Icons.pending,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        status,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isCompleted && completedAt.isNotEmpty 
                        ? _getRelativeTime(completedAt)
                        : 'In progress',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _toggleExpand(cardKey),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: AnimatedRotation(
                      duration: const Duration(milliseconds: 300),
                      turns: isExpanded ? 0.5 : 0.0,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Responder Info
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      responderName.isNotEmpty ? responderName[0].toUpperCase() : '?',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        responderName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              responderType,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.person_outline,
                                  color: Colors.white.withOpacity(0.7),
                                  size: 10,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'User: $userName',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            // ============================================================
            // EXPANDED VIEW
            // ============================================================
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 300),
              crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Container(height: 1, color: Colors.white.withOpacity(0.2)),
                  const SizedBox(height: 12),
                  
                  // ============================================================
                  // ✅ RESPONSE DURATION - GREEN THEMED CONTAINER (AT THE TOP)
                  // ============================================================
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.green.shade400.withOpacity(0.2),
                          Colors.green.shade600.withOpacity(0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.green.shade300.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.timer_rounded,
                          color: Colors.green.shade300,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Completion Time: ',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                        Text(
                          isCompleted ? durationText : 'In Progress',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade300,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // ============================================================
                  // RESPONDER INFO SECTION
                  // ============================================================
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Icon(
                            Icons.people_alt_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Responder Info',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  
                  // Responder ID (copyable)
                  _buildTwoColumnInfoRow(
                    label: 'Responder ID:',
                    value: responderId,
                    isCopyable: true,
                    copyValue: responderId,
                    copyLabel: 'Responder ID',
                  ),
                  
                  _buildTwoColumnInfoRow(
                    label: 'Responder Name:',
                    value: responderName,
                  ),
                  
                  _buildTwoColumnInfoRow(
                    label: 'Responder Type:',
                    value: responderType,
                  ),
                  
                  if (responderPhone.isNotEmpty)
                    _buildTwoColumnInfoRow(
                      label: 'Responder Phone:',
                      value: responderPhone,
                    ),
                  
                  if (responderEmail.isNotEmpty)
                    _buildTwoColumnInfoRow(
                      label: 'Responder Email:',
                      value: responderEmail,
                    ),
                  
                  const SizedBox(height: 8),
                  Container(height: 1, color: Colors.white.withOpacity(0.1)),
                  const SizedBox(height: 8),
                  
                  // ============================================================
                  // USER INFO SECTION
                  // ============================================================
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Icon(
                            Icons.person_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'User Info',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  
                  // User ID (copyable)
                  _buildTwoColumnInfoRow(
                    label: 'User ID:',
                    value: userId,
                    isCopyable: true,
                    copyValue: userId,
                    copyLabel: 'User ID',
                  ),
                  
                  _buildTwoColumnInfoRow(
                    label: 'User Name:',
                    value: userName,
                  ),
                  
                  // User Address - Copyable and goes to next line
                  _buildTwoColumnInfoRow(
                    label: 'User Address:',
                    value: userAddress,
                    isCopyable: true,
                    copyValue: userAddress,
                    copyLabel: 'User Address',
                    isAddress: true,
                  ),
                  
                  if (userPhone.isNotEmpty)
                    _buildTwoColumnInfoRow(
                      label: 'User Phone:',
                      value: userPhone,
                    ),
                  
                  if (userEmail.isNotEmpty)
                    _buildTwoColumnInfoRow(
                      label: 'User Email:',
                      value: userEmail,
                    ),
                  
                  const SizedBox(height: 8),
                  Container(height: 1, color: Colors.white.withOpacity(0.1)),
                  const SizedBox(height: 8),
                  
                  // ============================================================
                  // EMERGENCY INFO SECTION
                  // ============================================================
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Emergency Info',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  
                  // Emergency ID (copyable)
                  _buildTwoColumnInfoRow(
                    label: 'Emergency ID:',
                    value: emergencyId,
                    isCopyable: true,
                    copyValue: emergencyId,
                    copyLabel: 'Emergency ID',
                  ),
                  
                  _buildTwoColumnInfoRow(
                    label: 'SOS Time:',
                    value: time.isNotEmpty ? time : 'Unknown',
                  ),
                  
                  // Completion Time - Keep the original one in Emergency Info
                  _buildTwoColumnInfoRow(
                    label: 'Resolved Time:',
                    value: isCompleted && completedAt.isNotEmpty 
                        ? completedAt 
                        : 'In Progress',
                  ),
                  
                  _buildTwoColumnInfoRow(
                    label: 'Distance:',
                    value: distance,
                  ),
                  
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(
                          width: 110,
                          child: Text(
                            'Description:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              description,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
}