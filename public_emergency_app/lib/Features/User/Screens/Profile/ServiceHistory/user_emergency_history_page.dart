import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:public_emergency_app/Common%20Widgets/constants.dart';

class UserEmergencyHistoryPage extends StatefulWidget {
  final String userId;
  
  const UserEmergencyHistoryPage({
    Key? key,
    required this.userId,
  }) : super(key: key);

  @override
  State<UserEmergencyHistoryPage> createState() => _UserEmergencyHistoryPageState();
}

class _UserEmergencyHistoryPageState extends State<UserEmergencyHistoryPage> {
  late DatabaseReference sosDoneRef;
  late DatabaseReference doctorDoneRef;
  final String firebaseDatabaseUrl =
      'https://emergencyresponse-0xyvwt-default-rtdb.asia-southeast1.firebasedatabase.app';
  
  // Filter state
  String _selectedFilter = 'All';
  String _selectedTimeFilter = 'Latest';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  
  List<Map<String, dynamic>> _allHistoryEntries = [];
  List<Map<String, dynamic>> _filteredHistoryEntries = [];
  Map<String, Map<String, dynamic>> _userCache = {};
  Map<String, Map<String, dynamic>> _responderCache = {};
  Map<String, Map<String, dynamic>> _doctorCache = {};
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
      doctorDoneRef = db.ref().child('Doctor_Done');
      
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
    if (normalized == 'doctor') {
      return 'Doctor';
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

  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}d ${duration.inHours % 24}h ${duration.inMinutes % 60}m';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m ${duration.inSeconds % 60}s';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    } else {
      return '${duration.inSeconds}s';
    }
  }

  // ============================================================
  // LOAD ALL DATA FROM SOS_Done & Doctor_Done
  // ============================================================
  Future<void> _loadAllDataAtOnce() async {
    try {
      print('=== LOADING HISTORY FOR USER: ${widget.userId} ===');
      
      final usersRef = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: firebaseDatabaseUrl,
      ).ref('Users');
      
      final respondersRef = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: firebaseDatabaseUrl,
      ).ref('Responders');
      
      final doctorsRef = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: firebaseDatabaseUrl,
      ).ref('Doctors');

      final results = await Future.wait([
        sosDoneRef.once(),
        doctorDoneRef.once(),
        usersRef.once(),
        respondersRef.once(),
        doctorsRef.once(),
      ]);

      final sosDoneSnapshot = results[0];
      final doctorDoneSnapshot = results[1];
      final usersSnapshot = results[2];
      final respondersSnapshot = results[3];
      final doctorsSnapshot = results[4];

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

      // Build responder cache (Police & Firefighter)
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

      // Build doctor cache
      if (doctorsSnapshot.snapshot.value != null) {
        final doctorsData = Map<dynamic, dynamic>.from(doctorsSnapshot.snapshot.value as Map);
        for (var doctorEntry in doctorsData.entries) {
          final doctorId = doctorEntry.key;
          final doctorData = Map<dynamic, dynamic>.from(doctorEntry.value);
          _doctorCache[doctorId] = {
            'name': doctorData['UserName']?.toString() ?? 'Unknown',
            'type': 'Doctor',
            'phone': doctorData['Phone']?.toString() ?? '',
            'email': doctorData['email']?.toString() ?? '',
            'profession': doctorData['Profession']?.toString() ?? 'Doctor',
          };
        }
      }

      final List<Map<String, dynamic>> entries = [];

      // ============================================================
      // PROCESS COMPLETED EMERGENCIES (SOS_Done) - FILTER BY USER
      // ============================================================
      if (sosDoneSnapshot.snapshot.value != null) {
        print('Processing COMPLETED emergencies from SOS_Done...');
        final sosDoneData = Map<dynamic, dynamic>.from(sosDoneSnapshot.snapshot.value as Map);

        for (var entry in sosDoneData.entries) {
          final emergencyId = entry.key;
          final emergencyData = Map<dynamic, dynamic>.from(entry.value);
          
          final userInfo = emergencyData['userInfo'] ?? {};
          final userId = userInfo['uid']?.toString() ?? '';
          
          if (userId != widget.userId) continue;
          
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
          String distance = emergencyData['distance']?.toString() ?? '0 km';

          entries.add({
            'serviceId': emergencyId,
            'serviceType': 'Responder',
            'providerId': responderId,
            'providerName': responderDetails['name'] ?? 'Unknown',
            'providerType': responderDetails['type'] ?? 'Unknown',
            'providerPhone': responderDetails['phone'] ?? '',
            'providerEmail': responderDetails['email'] ?? '',
            'providerProfession': '',
            'userName': userDetails['name'] ?? 'Unknown User',
            'userId': userId,
            'userPhone': userDetails['phone'] ?? '',
            'userEmail': userDetails['email'] ?? '',
            'userAddress': userAddress,
            'time': sosTime,
            'assignedAt': emergencyData['assignedAt']?.toString() ?? '',
            'completedAt': formattedCompletionTime,
            'distance': distance,
            'responseTime': responseTime,
            'sessionTime': 'N/A',
            'description': emergencyDataFields['description']?.toString() ?? '',
            'status': 'Completed',
            'isCompleted': true,
            'displayType': responderDetails['type'] ?? 'Unknown',
          });
        }
      }

      // ============================================================
      // PROCESS DOCTOR COMPLETED (Doctor_Done) - FILTER BY USER
      // ============================================================
      if (doctorDoneSnapshot.snapshot.value != null) {
        print('Processing COMPLETED doctor requests from Doctor_Done...');
        final doctorDoneData = Map<dynamic, dynamic>.from(doctorDoneSnapshot.snapshot.value as Map);

        for (var entry in doctorDoneData.entries) {
          final requestId = entry.key;
          final requestData = Map<dynamic, dynamic>.from(entry.value);
          
          final userInfo = requestData['userInfo'] ?? {};
          final userId = userInfo['uid']?.toString() ?? '';
          
          if (userId != widget.userId) continue;
          
          final userDetails = _userCache[userId] ?? {
            'name': userInfo['name']?.toString() ?? 'Unknown User',
            'phone': userInfo['phone']?.toString() ?? '',
            'email': userInfo['email']?.toString() ?? '',
            'address': userInfo['address']?.toString() ?? '',
          };

          final doctorInfo = requestData['completedBy'] ?? {};
          final doctorId = doctorInfo['uid']?.toString() ?? '';
          final doctorDetails = _doctorCache[doctorId] ?? {
            'name': doctorInfo['name']?.toString() ?? 'Unknown',
            'type': 'Doctor',
            'phone': doctorInfo['phone']?.toString() ?? '',
            'email': doctorInfo['email']?.toString() ?? '',
            'profession': 'Doctor',
          };

          String requestTime = 'Unknown time';
          if (requestData['requestTimeFormatted'] != null) {
            requestTime = requestData['requestTimeFormatted'].toString();
          } else if (requestData['requestTime'] != null) {
            try {
              final requestTimeMs = requestData['requestTime'] as int;
              final requestDateTime = DateTime.fromMillisecondsSinceEpoch(requestTimeMs);
              requestTime = _formatDateTime(requestDateTime);
            } catch (e) {
              requestTime = 'Unknown time';
            }
          }

          String sessionTime = requestData['sessionTime']?.toString() ?? 'N/A';
          if (sessionTime == 'N/A' && requestData['sessionTimeMs'] != null) {
            try {
              final sessionTimeMs = requestData['sessionTimeMs'] as int;
              final duration = Duration(milliseconds: sessionTimeMs);
              sessionTime = _formatDuration(duration);
            } catch (e) {
              sessionTime = 'N/A';
            }
          }

          // Format completion time
          String formattedCompletionTime = 'In Progress';
          if (requestData['completedAt'] != null) {
            try {
              String completionStr = requestData['completedAt'].toString();
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
              formattedCompletionTime = requestData['completedAt']?.toString() ?? 'In Progress';
            }
          }

          entries.add({
            'serviceId': requestId,
            'serviceType': 'Doctor',
            'providerId': doctorId,
            'providerName': doctorDetails['name'] ?? 'Unknown Doctor',
            'providerType': 'Doctor',
            'providerPhone': doctorDetails['phone'] ?? '',
            'providerEmail': doctorDetails['email'] ?? '',
            'providerProfession': doctorDetails['profession'] ?? 'Doctor',
            'userName': userDetails['name'] ?? 'Unknown User',
            'userId': userId,
            'userPhone': userDetails['phone'] ?? '',
            'userEmail': userDetails['email'] ?? '',
            'userAddress': '',
            'time': requestTime,
            'assignedAt': requestData['assignedAt']?.toString() ?? '',
            'completedAt': formattedCompletionTime,
            'distance': 'N/A',
            'responseTime': 'N/A',
            'sessionTime': sessionTime,
            'description': '',
            'status': 'Completed',
            'isCompleted': true,
            'displayType': 'Doctor',
          });
        }
      }

      entries.sort((a, b) {
        final aTime = a['completedAt']?.toString() ?? '';
        final bTime = b['completedAt']?.toString() ?? '';
        return bTime.compareTo(aTime);
      });

      print('Total history entries found for user ${widget.userId}: ${entries.length}');

      setState(() {
        _allHistoryEntries = entries;
        _applyFilters();
        if (entries.isEmpty) {
          _errorMessage = 'No history found';
        }
      });
    } catch (e) {
      print('Error loading history: $e');
      setState(() {
        _errorMessage = 'Error loading history: $e';
      });
    }
  }

  // ============================================================
  // ✅ APPLY FILTERS
  // ============================================================
  void _applyFilters() {
    List<Map<String, dynamic>> filtered = List.from(_allHistoryEntries);
    
    // Filter by Type (All / Police / Firefighter / Doctor)
    if (_selectedFilter == 'Police') {
      filtered = filtered.where((entry) => entry['displayType'] == 'Police').toList();
    } else if (_selectedFilter == 'Firefighter') {
      filtered = filtered.where((entry) => entry['displayType'] == 'Firefighter').toList();
    } else if (_selectedFilter == 'Doctor') {
      filtered = filtered.where((entry) => entry['displayType'] == 'Doctor').toList();
    }
    
    // Search: provider name, provider ID, service ID
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase().trim();
      filtered = filtered.where((entry) {
        final providerName = entry['providerName']?.toString().toLowerCase() ?? '';
        final providerId = entry['providerId']?.toString().toLowerCase() ?? '';
        final serviceId = entry['serviceId']?.toString().toLowerCase() ?? '';
        
        return providerName.contains(query) || 
               providerId.contains(query) || 
               serviceId.contains(query);
      }).toList();
    }
    
    // Apply time-based filter
    filtered = _applyTimeFilter(filtered);
    
    // Apply sort order
    if (_selectedTimeFilter == 'Latest' || _selectedTimeFilter == 'Today' || 
        _selectedTimeFilter == 'Week' || _selectedTimeFilter == 'Month' || _selectedTimeFilter == 'Year') {
      filtered.sort((a, b) {
        final aTime = a['completedAt']?.toString() ?? '';
        final bTime = b['completedAt']?.toString() ?? '';
        return bTime.compareTo(aTime);
      });
    } else if (_selectedTimeFilter == 'Oldest') {
      filtered.sort((a, b) {
        final aTime = a['completedAt']?.toString() ?? '';
        final bTime = b['completedAt']?.toString() ?? '';
        return aTime.compareTo(bTime);
      });
    }
    
    setState(() {
      _filteredHistoryEntries = filtered;
    });
  }

  List<Map<String, dynamic>> _applyTimeFilter(List<Map<String, dynamic>> entries) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    if (_selectedTimeFilter == 'Latest' || _selectedTimeFilter == 'Oldest') {
      return entries;
    }
    
    return entries.where((entry) {
      final completedAt = entry['completedAt']?.toString();
      if (completedAt == null || completedAt.isEmpty) return false;
      
      try {
        DateTime? date;
        if (completedAt.contains(' ') && completedAt.contains(':')) {
          final parts = completedAt.split(' ');
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
          date = DateTime.parse(completedAt);
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
  // ✅ HANDLE TYPE FILTER CLICK
  // ============================================================
  void _handleTypeFilterClick(String filter) {
    setState(() {
      _selectedFilter = filter;
      _applyFilters();
    });
  }

  // ============================================================
  // ✅ HANDLE TIME FILTER CLICK
  // ============================================================
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

  Widget _buildTwoColumnInfoRow({
    required String label,
    required String value,
    bool isCopyable = false,
    String copyValue = '',
    String copyLabel = '',
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

  Widget _buildTypeFilterWidget() {
    final int totalCount = _allHistoryEntries.length;
    final int policeCount = _allHistoryEntries.where((entry) => entry['displayType'] == 'Police').length;
    final int firefighterCount = _allHistoryEntries.where((entry) => entry['displayType'] == 'Firefighter').length;
    final int doctorCount = _allHistoryEntries.where((entry) => entry['displayType'] == 'Doctor').length;

    final filters = [
      {'label': 'All', 'icon': Icons.list_alt, 'count': totalCount},
      {'label': 'Police', 'icon': Icons.local_police, 'count': policeCount},
      {'label': 'Firefighter', 'icon': Icons.fire_truck, 'count': firefighterCount},
      {'label': 'Doctor', 'icon': Icons.medical_services, 'count': doctorCount},
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
        height: 34,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: filters.length,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          itemBuilder: (context, index) {
            final filter = filters[index];
            final label = filter['label'] as String;
            final icon = filter['icon'] as IconData;
            final count = filter['count'] as int;
            final isSelected = _selectedFilter == label;
            
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _buildTypeFilterChip(
                label: label,
                filterType: label,
                icon: icon,
                count: count,
                isSelected: isSelected,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTypeFilterChip({
    required String label,
    required String filterType,
    required IconData icon,
    required int count,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () => _handleTypeFilterClick(filterType),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
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
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey.shade700,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 10,
              ),
            ),
            const SizedBox(width: 3),
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
      onTap: () => _handleTimeFilterClick(filterType),
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
                      'My Emergency History',
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
                    'Loading history...',
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
                        hintText: 'Search by Provider Name, ID or Service ID...',
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
                _buildTypeFilterWidget(),
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
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _searchQuery.isNotEmpty
                                    ? Icons.search_off_rounded
                                    : Icons.history_rounded,
                                size: 70,
                                color: Colors.grey.shade300,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'No results found'
                                    : 'No history found',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              if (_searchQuery.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Try searching by Provider name or ID',
                                    style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
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

 Widget _buildHistoryCard(Map<String, dynamic> entry) {
  final isCompleted = entry['isCompleted'] ?? false;
  final serviceType = entry['serviceType'] ?? 'Unknown';
  final providerName = entry['providerName'] ?? 'Unknown';
  final providerType = entry['providerType'] ?? 'Unknown';
  final providerPhone = entry['providerPhone'] ?? '';
  final providerEmail = entry['providerEmail'] ?? '';
  final providerId = entry['providerId'] ?? 'N/A';
  final providerProfession = entry['providerProfession'] ?? '';
  final serviceId = entry['serviceId'] ?? 'N/A';
  final time = entry['time'] ?? '';
  final completedAt = entry['completedAt'] ?? '';
  final assignedAt = entry['assignedAt'] ?? '';
  final distance = entry['distance'] ?? 'N/A';
  final responseTime = entry['responseTime'] ?? 'N/A';
  final sessionTime = entry['sessionTime'] ?? 'N/A';
  final description = entry['description'] ?? '';
  final status = entry['status'] ?? 'Active';
  final displayType = entry['displayType'] ?? 'Unknown';
  
  final bool isDoctor = serviceType == 'Doctor';
  final bool isPolice = displayType == 'Police';
  final bool isFirefighter = displayType == 'Firefighter';

  final String cardKey = entry['serviceId'] ?? DateTime.now().toString();
  final bool isExpanded = _expandedCards.contains(cardKey);
  
  Color primaryColor;
  Color accentColor;
  
  if (isPolice) {
    primaryColor = const Color(0xFF0F4C5C);
    accentColor = const Color(0xFF1A7A8C);
  } else if (isFirefighter) {
    primaryColor = const Color(0xFF8B4513);
    accentColor = const Color(0xFFCC5500);
  } else if (isDoctor) {
    primaryColor = const Color(0xFF1A4A3C);
    accentColor = const Color(0xFF2A7A5C);
  } else {
    primaryColor = const Color(0xFF0F4C5C);
    accentColor = const Color(0xFF1A7A8C);
  }

  String _getDurationBetweenTimes(String startTimeStr, String completedAtStr) {
    if (startTimeStr.isEmpty || completedAtStr.isEmpty || startTimeStr == 'Unknown time') {
      return 'N/A';
    }
    try {
      DateTime? startDateTime;
      DateTime? endDateTime;
      
      if (startTimeStr.contains(' ') && startTimeStr.contains(':')) {
        final startParts = startTimeStr.split(' ');
        if (startParts.length == 2) {
          final startDateParts = startParts[1].split('/');
          final startTimeParts = startParts[0].split(':');
          if (startDateParts.length == 3 && startTimeParts.length == 3) {
            startDateTime = DateTime(
              int.parse(startDateParts[2]),
              int.parse(startDateParts[1]),
              int.parse(startDateParts[0]),
              int.parse(startTimeParts[0]),
              int.parse(startTimeParts[1]),
              int.parse(startTimeParts[2]),
            );
          }
        }
      }
      
      if (completedAtStr.contains(' ') && completedAtStr.contains(':')) {
        final endParts = completedAtStr.split(' ');
        if (endParts.length == 2) {
          final endDateParts = endParts[1].split('/');
          final endTimeParts = endParts[0].split(':');
          if (endDateParts.length == 3 && endTimeParts.length == 3) {
            endDateTime = DateTime(
              int.parse(endDateParts[2]),
              int.parse(endDateParts[1]),
              int.parse(endDateParts[0]),
              int.parse(endTimeParts[0]),
              int.parse(endTimeParts[1]),
              int.parse(endTimeParts[2]),
            );
          }
        }
      }
      
      if (startDateTime != null && endDateTime != null) {
        final difference = endDateTime.difference(startDateTime);
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
                      providerName.isNotEmpty ? providerName[0].toUpperCase() : '?',
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
                        isDoctor ? 'Dr. $providerName' : providerName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // ❌ REMOVED the service type icon (Responder/Doctor badge)
                      // Only show the provider type badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isDoctor 
                              ? (providerProfession.isNotEmpty ? providerProfession : 'Doctor')
                              : displayType,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
                  
                  // SERVICE DURATION CONTAINER
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDoctor
                            ? [
                                Colors.blue.shade400.withOpacity(0.2),
                                Colors.blue.shade600.withOpacity(0.1),
                              ]
                            : [
                                Colors.green.shade400.withOpacity(0.2),
                                Colors.green.shade600.withOpacity(0.1),
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDoctor
                            ? Colors.blue.shade300.withOpacity(0.3)
                            : Colors.green.shade300.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.timer_rounded,
                          color: isDoctor ? Colors.blue.shade300 : Colors.green.shade300,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isDoctor ? 'Session Duration: ' : 'Completion Time: ',
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
                            color: isDoctor ? Colors.blue.shade300 : Colors.green.shade300,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // PROVIDER INFO SECTION
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
                            isDoctor ? Icons.medical_services_rounded : Icons.people_alt_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isDoctor ? 'Doctor Info' : 'Responder Info',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  
                  _buildTwoColumnInfoRow(
                    label: isDoctor ? 'Doctor ID:' : 'Responder ID:',
                    value: providerId,
                    isCopyable: true,
                    copyValue: providerId,
                    copyLabel: isDoctor ? 'Doctor ID' : 'Responder ID',
                  ),
                  
                  _buildTwoColumnInfoRow(
                    label: isDoctor ? 'Doctor Name:' : 'Responder Name:',
                    value: isDoctor ? 'Dr. $providerName' : providerName,
                  ),
                  
                  if (!isDoctor)
                    _buildTwoColumnInfoRow(
                      label: 'Responder Type:',
                      value: displayType,
                    ),
                  
                  if (providerPhone.isNotEmpty)
                    _buildTwoColumnInfoRow(
                      label: isDoctor ? 'Doctor Phone:' : 'Responder Phone:',
                      value: providerPhone,
                    ),
                  
                  if (isDoctor && providerEmail.isNotEmpty)
                    _buildTwoColumnInfoRow(
                      label: 'Doctor Email:',
                      value: providerEmail,
                    ),
                  
                  const SizedBox(height: 8),
                  Container(height: 1, color: Colors.white.withOpacity(0.1)),
                  const SizedBox(height: 8),
                  
                  // SESSION INFO SECTION
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
                            isDoctor ? Icons.description_rounded : Icons.warning_amber_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isDoctor ? 'Session Info' : 'Emergency Info',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  
                  _buildTwoColumnInfoRow(
                    label: isDoctor ? 'Request ID:' : 'Emergency ID:',
                    value: serviceId,
                    isCopyable: true,
                    copyValue: serviceId,
                    copyLabel: isDoctor ? 'Request ID' : 'Emergency ID',
                  ),
                  
                  _buildTwoColumnInfoRow(
                    label: isDoctor ? 'Request Time:' : 'SOS Time:',
                    value: time.isNotEmpty ? time : 'Unknown',
                  ),
                  
                  _buildTwoColumnInfoRow(
                    label: isDoctor ? 'Completion Time:' : 'Resolved Time:',
                    value: isCompleted && completedAt.isNotEmpty 
                        ? completedAt 
                        : 'In Progress',
                  ),
                  
                  if (distance.isNotEmpty && distance != 'N/A' && !isDoctor)
                    _buildTwoColumnInfoRow(
                      label: 'Distance:',
                      value: distance,
                    ),
                  
                  if (description.isNotEmpty && !isDoctor) ...[
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