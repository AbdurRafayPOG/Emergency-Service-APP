import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:public_emergency_app/Common%20Widgets/constants.dart';

class DocterHistoryScreen extends StatefulWidget {
  const DocterHistoryScreen({Key? key}) : super(key: key);

  @override
  State<DocterHistoryScreen> createState() => _DocterHistoryScreenState();
}

class _DocterHistoryScreenState extends State<DocterHistoryScreen> {
  late DatabaseReference doctorDoneRef;
  late DatabaseReference assignedDoctorsRef;  // ✅ FIXED: Use assigned_doctors
  final String firebaseDatabaseUrl =
      'https://emergencyresponse-0xyvwt-default-rtdb.asia-southeast1.firebasedatabase.app';
  
  // Filter state
  String _selectedStatusFilter = 'All';
  String _selectedTimeFilter = 'Latest';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  
  List<Map<String, dynamic>> _allHistoryEntries = [];
  List<Map<String, dynamic>> _filteredHistoryEntries = [];
  Map<String, Map<String, dynamic>> _userCache = {};
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
      doctorDoneRef = db.ref().child('Doctor_Done');
      assignedDoctorsRef = db.ref().child('assigned_doctors');  // ✅ FIXED
      
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

  String _formatDateTimeFromTimestamp(int timestamp) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return _formatDateTime(dateTime);
  }

  // ============================================================
  // ✅ LOAD DOCTOR HISTORY DATA (Completed + Active from assigned_doctors)
  // ============================================================
  Future<void> _loadAllDataAtOnce() async {
    try {
      print('=== LOADING DOCTOR HISTORY (Completed + Active) ===');
      
      final usersRef = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: firebaseDatabaseUrl,
      ).ref('Users');
      
      final doctorsRef = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: firebaseDatabaseUrl,
      ).ref('Doctors');

      final results = await Future.wait([
        doctorDoneRef.once(),
        assignedDoctorsRef.once(),  // ✅ FIXED
        usersRef.once(),
        doctorsRef.once(),
      ]);

      final doctorDoneSnapshot = results[0];
      final assignedDoctorsSnapshot = results[1];  // ✅ FIXED
      final usersSnapshot = results[2];
      final doctorsSnapshot = results[3];

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
          };
        }
      }

      // Build doctor cache from 'Doctors' node
      if (doctorsSnapshot.snapshot.value != null) {
        final doctorsData = Map<dynamic, dynamic>.from(doctorsSnapshot.snapshot.value as Map);
        for (var doctorEntry in doctorsData.entries) {
          final doctorId = doctorEntry.key;
          final doctorData = Map<dynamic, dynamic>.from(doctorEntry.value);
          _doctorCache[doctorId] = {
            'name': doctorData['UserName']?.toString() ?? 'Unknown Doctor',
            'type': 'Doctor',
            'phone': doctorData['Phone']?.toString() ?? '',
            'email': doctorData['email']?.toString() ?? '',
            'profession': doctorData['Profession']?.toString() ?? '',
          };
        }
      }

      final List<Map<String, dynamic>> entries = [];

      // ============================================================
      // ✅ PROCESS COMPLETED DOCTOR REQUESTS (Doctor_Done)
      // ============================================================
      if (doctorDoneSnapshot.snapshot.value != null) {
        print('Processing COMPLETED doctor requests from Doctor_Done...');
        final doctorDoneData = Map<dynamic, dynamic>.from(doctorDoneSnapshot.snapshot.value as Map);

        for (var entry in doctorDoneData.entries) {
          final requestId = entry.key;
          final requestData = Map<dynamic, dynamic>.from(entry.value);
          
          final userInfo = requestData['userInfo'] ?? {};
          final userId = userInfo['uid']?.toString() ?? '';
          final userDetails = _userCache[userId] ?? {
            'name': userInfo['name']?.toString() ?? 'Unknown User',
            'phone': userInfo['phone']?.toString() ?? '',
            'email': userInfo['email']?.toString() ?? '',
          };

          final doctorInfo = requestData['completedBy'] ?? {};
          final doctorId = doctorInfo['uid']?.toString() ?? '';
          
          Map<String, dynamic> doctorDetails;
          if (_doctorCache.containsKey(doctorId)) {
            doctorDetails = _doctorCache[doctorId]!;
          } else {
            doctorDetails = {
              'name': doctorInfo['name']?.toString() ?? 'Unknown Doctor',
              'type': 'Doctor',
              'phone': doctorInfo['phone']?.toString() ?? '',
              'email': doctorInfo['email']?.toString() ?? '',
              'profession': '',
            };
          }

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
          bool isCompleted = true;
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
            'requestId': requestId,
            'doctorId': doctorId,
            'doctorName': doctorDetails['name'] ?? 'Unknown Doctor',
            'doctorType': doctorDetails['type'] ?? 'Doctor',
            'doctorPhone': doctorDetails['phone'] ?? '',
            'doctorEmail': doctorDetails['email'] ?? '',
            'doctorProfession': doctorDetails['profession'] ?? '',
            'userName': userDetails['name'] ?? 'Unknown User',
            'userId': userId,
            'userPhone': userDetails['phone'] ?? '',
            'userEmail': userDetails['email'] ?? '',
            'time': requestTime,
            'assignedAt': requestData['assignedAt']?.toString() ?? '',
            'completedAt': formattedCompletionTime,
            'sessionTime': sessionTime,
            'responseTime': requestData['responseTime']?.toString() ?? 'N/A',
            'description': '',
            'isCompleted': isCompleted,
            'status': 'Completed',
            'source': 'Doctor_Done',
          });
        }
      }

      // ============================================================
      // ✅ PROCESS ACTIVE DOCTOR REQUESTS (assigned_doctors)
      // ============================================================
      if (assignedDoctorsSnapshot.snapshot.value != null) {
        print('Processing ACTIVE doctor requests from assigned_doctors...');
        final assignedDoctorsData = Map<dynamic, dynamic>.from(assignedDoctorsSnapshot.snapshot.value as Map);

        for (var doctorEntry in assignedDoctorsData.entries) {
          final doctorId = doctorEntry.key;
          final doctorData = Map<dynamic, dynamic>.from(doctorEntry.value);
          
          for (var requestEntry in doctorData.entries) {
            final requestId = requestEntry.key;
            final requestData = Map<dynamic, dynamic>.from(requestEntry.value);
            
            // Check status - skip if completed or cancelled
            final status = requestData['status']?.toString() ?? 'assigned';
            if (status == 'completed' || status == 'cancelled') continue;
            
            // Get user info from request data
            final userId = requestData['userId']?.toString() ?? '';
            final userDetails = _userCache[userId] ?? {
              'name': requestData['userName']?.toString() ?? 'Unknown User',
              'phone': requestData['userPhone']?.toString() ?? '',
              'email': requestData['userEmail']?.toString() ?? '',
            };

            // Get doctor details from cache or request data
            Map<String, dynamic> doctorDetails;
            if (_doctorCache.containsKey(doctorId)) {
              doctorDetails = _doctorCache[doctorId]!;
            } else {
              doctorDetails = {
                'name': requestData['doctorName']?.toString() ?? 'Unknown Doctor',
                'type': 'Doctor',
                'phone': '',
                'email': '',
                'profession': requestData['profession']?.toString() ?? '',
              };
            }

            // Get assigned time from timestamp
            String assignedAt = 'Unknown time';
            if (requestData['assignedAt'] != null) {
              try {
                final assignedMs = requestData['assignedAt'] as int;
                assignedAt = _formatDateTimeFromTimestamp(assignedMs);
              } catch (e) {
                assignedAt = requestData['assignedAt']?.toString() ?? 'Unknown time';
              }
            }

            // Request time is same as assigned time for active requests
            String requestTime = assignedAt;

            entries.add({
              'requestId': requestId,
              'doctorId': doctorId,
              'doctorName': doctorDetails['name'] ?? 'Unknown Doctor',
              'doctorType': doctorDetails['type'] ?? 'Doctor',
              'doctorPhone': doctorDetails['phone'] ?? '',
              'doctorEmail': doctorDetails['email'] ?? '',
              'doctorProfession': doctorDetails['profession'] ?? '',
              'userName': userDetails['name'] ?? 'Unknown User',
              'userId': userId,
              'userPhone': userDetails['phone'] ?? '',
              'userEmail': userDetails['email'] ?? '',
              'time': requestTime,
              'assignedAt': assignedAt,
              'completedAt': 'In Progress',
              'sessionTime': 'N/A',
              'responseTime': 'N/A',
              'description': requestData['description']?.toString() ?? '',
              'isCompleted': false,
              'status': 'Active',
              'source': 'assigned_doctors',
            });
          }
        }
      }

      // Sort by time (newest first)
      entries.sort((a, b) {
        final aTime = a['time']?.toString() ?? '';
        final bTime = b['time']?.toString() ?? '';
        return bTime.compareTo(aTime);
      });

      print('Total doctor history entries found: ${entries.length}');
      print('  - Completed: ${entries.where((e) => e['isCompleted'] == true).length}');
      print('  - Active: ${entries.where((e) => e['isCompleted'] == false).length}');

      setState(() {
        _allHistoryEntries = entries;
        _applyFilters();
        if (entries.isEmpty) {
          _errorMessage = 'No doctor history found';
        }
      });
    } catch (e) {
      print('Error loading doctor history: $e');
      setState(() {
        _errorMessage = 'Error loading doctor history: $e';
      });
    }
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
  // ✅ APPLY FILTERS
  // ============================================================
  void _applyFilters() {
    List<Map<String, dynamic>> filtered = List.from(_allHistoryEntries);
    
    if (_selectedStatusFilter == 'Active') {
      filtered = filtered.where((entry) => entry['isCompleted'] == false).toList();
    } else if (_selectedStatusFilter == 'Completed') {
      filtered = filtered.where((entry) => entry['isCompleted'] == true).toList();
    }
    
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase().trim();
      filtered = filtered.where((entry) {
        final doctorName = entry['doctorName']?.toString().toLowerCase() ?? '';
        final doctorId = entry['doctorId']?.toString().toLowerCase() ?? '';
        final doctorPhone = entry['doctorPhone']?.toString().toLowerCase() ?? '';
        final doctorEmail = entry['doctorEmail']?.toString().toLowerCase() ?? '';
        final doctorProfession = entry['doctorProfession']?.toString().toLowerCase() ?? '';
        final userName = entry['userName']?.toString().toLowerCase() ?? '';
        final userId = entry['userId']?.toString().toLowerCase() ?? '';
        final userPhone = entry['userPhone']?.toString().toLowerCase() ?? '';
        final userEmail = entry['userEmail']?.toString().toLowerCase() ?? '';
        final requestId = entry['requestId']?.toString().toLowerCase() ?? '';
        final status = entry['status']?.toString().toLowerCase() ?? '';
        final source = entry['source']?.toString().toLowerCase() ?? '';
        
        return doctorName.contains(query) ||
               doctorId.contains(query) ||
               doctorPhone.contains(query) ||
               doctorEmail.contains(query) ||
               doctorProfession.contains(query) ||
               userName.contains(query) ||
               userId.contains(query) ||
               userPhone.contains(query) ||
               userEmail.contains(query) ||
               requestId.contains(query) ||
               status.contains(query) ||
               source.contains(query);
      }).toList();
    }
    
    filtered = _applyTimeFilter(filtered);
    
    if (_selectedTimeFilter == 'Latest' || _selectedTimeFilter == 'Today' || 
        _selectedTimeFilter == 'Week' || _selectedTimeFilter == 'Month' || _selectedTimeFilter == 'Year') {
      filtered.sort((a, b) {
        final aTime = a['time']?.toString() ?? '';
        final bTime = b['time']?.toString() ?? '';
        return bTime.compareTo(aTime);
      });
    } else if (_selectedTimeFilter == 'Oldest') {
      filtered.sort((a, b) {
        final aTime = a['time']?.toString() ?? '';
        final bTime = b['time']?.toString() ?? '';
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
      final time = entry['time']?.toString();
      if (time == null || time.isEmpty || time == 'Unknown time') return false;
      
      try {
        final parts = time.split(' ');
        if (parts.length == 2) {
          final dateParts = parts[1].split('/');
          if (dateParts.length == 3) {
            final day = int.parse(dateParts[0]);
            final month = int.parse(dateParts[1]);
            final year = int.parse(dateParts[2]);
            final date = DateTime(year, month, day);
            
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
          }
        }
        return false;
      } catch (e) {
        return false;
      }
    }).toList();
  }

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

  void _handleFilterClick(String filterType) {
    setState(() {
      _selectedStatusFilter = filterType;
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
    if (dateString == null || dateString.isEmpty || dateString == 'In Progress' || dateString == 'Unknown time') {
      return dateString ?? 'Unknown';
    }
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
  // ✅ TIME FILTER WIDGET
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
  // ✅ FILTER WIDGET - All, Active, Completed
  // ============================================================
  Widget _buildFilterWidget() {
    final int totalAll = _allHistoryEntries.length;
    final int totalActive = _allHistoryEntries.where((entry) => entry['isCompleted'] == false).length;
    final int totalCompleted = _allHistoryEntries.where((entry) => entry['isCompleted'] == true).length;

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
      child: Row(
        children: [
          Expanded(
            child: _buildFilterChip(
              label: 'All',
              filterType: 'All',
              icon: Icons.list_alt,
              count: totalAll,
              isSelected: _selectedStatusFilter == 'All',
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
            ),
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
  }) {
    return GestureDetector(
      onTap: () {
        _handleFilterClick(filterType);
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
                if (isCopyable && value.isNotEmpty && value != 'N/A' && value != 'Not provided' && value != 'In Progress')
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
        backgroundColor: Color(color),
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
                      'Doctor History',
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
                        color: Color(color),
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
                    'Loading doctor history...',
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
                        hintText: 'Search by Doctor Name, ID, User, ID, Request ID...',
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
                
                _buildFilterWidget(),
                
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
                                      : Icons.medical_services_rounded,
                                  size: 70,
                                  color: Colors.grey.shade300,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? 'No results found'
                                      : 'No doctor history found',
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
                                      'Try searching by Doctor name, ID, User name, ID, or Request ID',
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
    final doctorName = entry['doctorName'] ?? 'Unknown Doctor';
    final doctorId = entry['doctorId'] ?? 'N/A';
    final doctorPhone = entry['doctorPhone'] ?? '';
    final doctorEmail = entry['doctorEmail'] ?? '';
    final doctorProfession = entry['doctorProfession'] ?? '';
    final userName = entry['userName'] ?? 'Unknown User';
    final userId = entry['userId'] ?? 'N/A';
    final userPhone = entry['userPhone'] ?? '';
    final userEmail = entry['userEmail'] ?? '';
    final requestId = entry['requestId'] ?? 'N/A';
    final time = entry['time'] ?? '';
    final completedAt = entry['completedAt'] ?? '';
    final assignedAt = entry['assignedAt'] ?? '';
    final sessionTime = entry['sessionTime'] ?? 'N/A';
    final status = entry['status'] ?? 'Active';
    final source = entry['source'] ?? 'Unknown';
    
    // Calculate duration between request time and completion time
    String _getDurationBetweenTimes(String requestTimeStr, String completedAtStr) {
      if (requestTimeStr.isEmpty || completedAtStr.isEmpty || requestTimeStr == 'Unknown time' || completedAtStr == 'In Progress') {
        return 'N/A';
      }
      
      try {
        DateTime? requestDateTime;
        DateTime? completedDateTime;
        
        if (requestTimeStr.contains(' ') && requestTimeStr.contains(':')) {
          final reqParts = requestTimeStr.split(' ');
          if (reqParts.length == 2) {
            final reqDateParts = reqParts[1].split('/');
            final reqTimeParts = reqParts[0].split(':');
            if (reqDateParts.length == 3 && reqTimeParts.length == 3) {
              requestDateTime = DateTime(
                int.parse(reqDateParts[2]),
                int.parse(reqDateParts[1]),
                int.parse(reqDateParts[0]),
                int.parse(reqTimeParts[0]),
                int.parse(reqTimeParts[1]),
                int.parse(reqTimeParts[2]),
              );
            }
          }
        }
        
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
        
        if (requestDateTime != null && completedDateTime != null) {
          final difference = completedDateTime.difference(requestDateTime);
          
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
    
    final String cardKey = entry['requestId'] ?? DateTime.now().toString();
    final bool isExpanded = _expandedCards.contains(cardKey);
    
    final Color primaryColor = const Color(0xFF1A4A3C);
    final Color accentColor = const Color(0xFF2A7A5C);

    // Get source badge color
    Color getSourceColor() {
      if (source == 'assigned_doctors') return Colors.orange.shade400;
      return Colors.green.shade400;
    }

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
                  const SizedBox(width: 8),
                  // ✅ Source Badge (Active/Completed)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: getSourceColor().withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: getSourceColor().withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      source == 'assigned_doctors' ? 'Active' : 'Completed',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: getSourceColor(),
                      ),
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
                      isCompleted && completedAt.isNotEmpty && completedAt != 'In Progress'
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
                        doctorName.isNotEmpty ? doctorName[0].toUpperCase() : '?',
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
                          'Dr. $doctorName',
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
                            if (doctorProfession.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  doctorProfession,
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
                    
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.blue.shade400.withOpacity(0.2),
                            Colors.blue.shade600.withOpacity(0.1),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.blue.shade300.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.timer_rounded,
                            color: Colors.blue.shade300,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isCompleted ? 'Session Duration: ' : 'Time Elapsed: ',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                          Text(
                            isCompleted ? durationText : sessionTime,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade300,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
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
                              Icons.medical_services_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Doctor Info',
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
                      label: 'Doctor ID:',
                      value: doctorId,
                      isCopyable: true,
                      copyValue: doctorId,
                      copyLabel: 'Doctor ID',
                    ),
                    
                    _buildTwoColumnInfoRow(
                      label: 'Doctor Name:',
                      value: 'Dr. $doctorName',
                    ),
                    
                    _buildTwoColumnInfoRow(
                      label: 'Doctor Phone:',
                      value: doctorPhone.isNotEmpty ? doctorPhone : 'Not provided',
                    ),
                    
                    _buildTwoColumnInfoRow(
                      label: 'Doctor Email:',
                      value: doctorEmail.isNotEmpty ? doctorEmail : 'Not provided',
                    ),
                    
                    const SizedBox(height: 8),
                    Container(height: 1, color: Colors.white.withOpacity(0.1)),
                    const SizedBox(height: 8),
                    
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
                              Icons.person_outline,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Patient Info',
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
                      label: 'Patient ID:',
                      value: userId,
                      isCopyable: true,
                      copyValue: userId,
                      copyLabel: 'Patient ID',
                    ),
                    
                    _buildTwoColumnInfoRow(
                      label: 'Patient Name:',
                      value: userName,
                    ),
                    
                    _buildTwoColumnInfoRow(
                      label: 'Patient Phone:',
                      value: userPhone.isNotEmpty ? userPhone : 'Not provided',
                    ),
                    
                    _buildTwoColumnInfoRow(
                      label: 'Patient Email:',
                      value: userEmail.isNotEmpty ? userEmail : 'Not provided',
                    ),
                    
                    const SizedBox(height: 8),
                    Container(height: 1, color: Colors.white.withOpacity(0.1)),
                    const SizedBox(height: 8),
                    
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
                              Icons.description_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Session Info',
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
                      label: 'Request ID:',
                      value: requestId,
                      isCopyable: true,
                      copyValue: requestId,
                      copyLabel: 'Request ID',
                    ),
                    
                    _buildTwoColumnInfoRow(
                      label: 'Request Time:',
                      value: time.isNotEmpty ? time : 'Unknown',
                    ),
                    
                    _buildTwoColumnInfoRow(
                      label: 'Assigned Time:',
                      value: assignedAt.isNotEmpty ? assignedAt : 'Not assigned',
                    ),
                    
                    _buildTwoColumnInfoRow(
                      label: 'Completion Time:',
                      value: isCompleted && completedAt.isNotEmpty && completedAt != 'In Progress'
                          ? completedAt 
                          : 'In Progress',
                    ),
                    
                    if (entry['description']?.isNotEmpty ?? false)
                      _buildTwoColumnInfoRow(
                        label: 'Description:',
                        value: entry['description'] ?? '',
                      ),
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