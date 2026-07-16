import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../Common Widgets/constants.dart';

class CompletedEmergenciesPage extends StatefulWidget {
  final String responderId;
  
  const CompletedEmergenciesPage({
    Key? key,
    required this.responderId,
  }) : super(key: key);

  @override
  State<CompletedEmergenciesPage> createState() => _CompletedEmergenciesPageState();
}

class _CompletedEmergenciesPageState extends State<CompletedEmergenciesPage> {
  late DatabaseReference sosDoneRef;
  final String firebaseDatabaseUrl =
      'https://emergencyresponse-0xyvwt-default-rtdb.asia-southeast1.firebasedatabase.app';
  bool _isLoading = true;
  String _selectedFilter = 'Latest';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final Set<String> _expandedCards = {};
  
  List<MapEntry<dynamic, dynamic>> _allEntries = [];
  List<MapEntry<dynamic, dynamic>> _filteredEntries = [];
  bool _dataFetched = false;

  @override
  void initState() {
    super.initState();
    _initializeDatabase();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
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
      await _fetchDataOnce();
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error initializing database: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchDataOnce() async {
    try {
      final snapshot = await sosDoneRef
          .orderByChild('completedBy/uid')
          .equalTo(widget.responderId)
          .once();
      
      if (snapshot.snapshot.value != null) {
        final data = Map<dynamic, dynamic>.from(snapshot.snapshot.value as Map);
        final entries = data.entries.toList();
        
        setState(() {
          _allEntries = entries;
          _dataFetched = true;
          _applyFilters();
        });
      } else {
        setState(() {
          _allEntries = [];
          _filteredEntries = [];
          _dataFetched = true;
        });
      }
    } catch (e) {
      debugPrint('Error fetching data: $e');
      setState(() {
        _dataFetched = true;
      });
    }
  }

  void _applyFilters() {
    List<MapEntry<dynamic, dynamic>> filtered = List.from(_allEntries);
    
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase().trim();
      filtered = filtered.where((entry) {
        final dataMap = Map<String, dynamic>.from(entry.value as Map);
        final userInfo = dataMap['userInfo'] ?? {};
        
        final userName = userInfo['name']?.toString().toLowerCase() ?? '';
        final userId = userInfo['uid']?.toString().toLowerCase() ?? '';
        final emergencyKey = entry.key.toString().toLowerCase();
        
        return userName.contains(query) || 
               userId.contains(query) || 
               emergencyKey.contains(query);
      }).toList();
    }
    
    filtered = _applyTimeFilter(filtered);
    
    if (_selectedFilter == 'Latest' || _selectedFilter == 'Today' || 
        _selectedFilter == 'Week' || _selectedFilter == 'Month' || _selectedFilter == 'Year') {
      filtered.sort((a, b) {
        final aTime = (a.value as Map)['completedAt']?.toString() ?? '';
        final bTime = (b.value as Map)['completedAt']?.toString() ?? '';
        return bTime.compareTo(aTime);
      });
    } else if (_selectedFilter == 'Oldest') {
      filtered.sort((a, b) {
        final aTime = (a.value as Map)['completedAt']?.toString() ?? '';
        final bTime = (b.value as Map)['completedAt']?.toString() ?? '';
        return aTime.compareTo(bTime);
      });
    }
    
    setState(() {
      _filteredEntries = filtered;
    });
  }

  List<MapEntry<dynamic, dynamic>> _applyTimeFilter(List<MapEntry<dynamic, dynamic>> entries) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    if (_selectedFilter == 'Latest' || _selectedFilter == 'Oldest') {
      return entries;
    }
    
    return entries.where((entry) {
      final dataMap = entry.value as Map;
      final completedAt = dataMap['completedAt']?.toString();
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
        
        switch (_selectedFilter) {
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

  void _handleSearch(String query) {
    setState(() {
      _searchQuery = query;
      _applyFilters();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    _handleSearch('');
  }

  void _handleFilterClick(String filter) {
    setState(() {
      _selectedFilter = filter;
      _applyFilters();
    });
  }

  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
    });
    await _fetchDataOnce();
    setState(() {
      _isLoading = false;
    });
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

  String _formatDate(String? isoString) {
    if (isoString == null) return 'Unknown';
    try {
      final date = DateTime.parse(isoString);
      final now = DateTime.now();
      final difference = now.difference(date);
      
      if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return isoString;
    }
  }

  // ============================================================
  // ✅ GET FORMATTED DATE TIME - Returns "HH:MM:SS DD/MM/YYYY"
  // ============================================================
  String _getFormattedDateTime(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'In Progress';
    
    try {
      // Check if it's already in the correct format "HH:MM:SS DD/MM/YYYY"
      if (dateString.contains(' ') && dateString.contains(':')) {
        final parts = dateString.split(' ');
        if (parts.length == 2) {
          final timeParts = parts[0].split(':');
          final dateParts = parts[1].split('/');
          if (timeParts.length == 3 && dateParts.length == 3) {
            // Already in correct format
            return dateString;
          }
        }
      }
      
      // Try to parse as DateTime
      DateTime? date;
      try {
        date = DateTime.parse(dateString);
      } catch (_) {
        // Try parsing as timestamp
        final ms = int.tryParse(dateString);
        if (ms != null) {
          date = DateTime.fromMillisecondsSinceEpoch(ms);
        }
      }
      
      if (date != null) {
        return _formatDateTime(date);
      }
      
      return dateString;
    } catch (e) {
      return dateString;
    }
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

  void _toggleExpand(String key) {
    setState(() {
      if (_expandedCards.contains(key)) {
        _expandedCards.remove(key);
      } else {
        _expandedCards.add(key);
      }
    });
  }

  Widget _buildFilterWidget() {
    final filters = [
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
        height: 34,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: filters.length,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          itemBuilder: (context, index) {
            final filter = filters[index];
            final label = filter['label'] as String;
            final icon = filter['icon'] as IconData;
            final isSelected = _selectedFilter == label;
            
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _buildFilterChip(
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

  Widget _buildFilterChip({
    required String label,
    required String filterType,
    required IconData icon,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () => _handleFilterClick(filterType),
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
                      'Completed Emergencies',
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
                    'Loading emergencies...',
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
                      focusNode: _searchFocusNode,
                      onChanged: _handleSearch,
                      decoration: InputDecoration(
                        hintText: 'Search by Username, User ID, or Emergency ID...',
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
                
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF0F4C5C),
                              const Color(0xFF0F4C5C).withOpacity(0.8),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_circle_outline,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${_filteredEntries.length} Completed',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (_searchQuery.isNotEmpty)
                        Text(
                          '${_filteredEntries.length} result${_filteredEntries.length != 1 ? 's' : ''} found',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
                
                Expanded(
                  child: _filteredEntries.isEmpty && _dataFetched
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                size: 60,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'No results found'
                                    : 'No completed emergencies yet',
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              if (_searchQuery.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Try adjusting your search',
                                    style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _refreshData,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: _filteredEntries.length,
                            itemBuilder: (context, index) {
                              final entry = _filteredEntries[index];
                              final dataMap = Map<String, dynamic>.from(entry.value as Map);
                              final userInfo = dataMap['userInfo'] ?? {};
                              final responderInfo = dataMap['completedBy'] ?? {};
                              final emergencyData = dataMap['emergencyData'] ?? {};
                              
                              final String userName = userInfo['name'] ?? 'Unknown User';
                              final String userPhone = userInfo['phone'] ?? 'N/A';
                              final String userAddress = emergencyData['userAddress']?.toString() ?? 'No Address';
                              final String completedAt = dataMap['completedAt']?.toString() ?? '';
                              final String responderName = responderInfo['name'] ?? 'Unknown Responder';
                              final String responderType = responderInfo['type'] ?? 'Responder';
                              final String distance = dataMap['distance'] ?? '';
                              final String emergencyDescription = emergencyData['description'] ?? '';
                              final String userUid = userInfo['uid']?.toString() ?? 'N/A';
                              final String emergencyId = entry.key.toString();
                              
                              String sosTime = 'Unknown time';
                              if (dataMap['sosTimeFormatted'] != null) {
                                sosTime = dataMap['sosTimeFormatted'].toString();
                              } else if (dataMap['sosTime'] != null) {
                                try {
                                  final sosTimeMs = dataMap['sosTime'] as int;
                                  final sosDateTime = DateTime.fromMillisecondsSinceEpoch(sosTimeMs);
                                  sosTime = _formatDateTime(sosDateTime);
                                } catch (e) {
                                  sosTime = 'Unknown time';
                                }
                              }
                              
                              String totalTime = dataMap['responseTime']?.toString() ?? 'N/A';
                              
                              final String cardKey = entry.key.toString();
                              final bool isExpanded = _expandedCards.contains(cardKey);

                              return GestureDetector(
                                onTap: () => _toggleExpand(cardKey),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF0F4C5C),
                                        Color(0xFF1A7A8C),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
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
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    Colors.green.shade400,
                                                    Colors.green.shade600,
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: Colors.green.shade300.withOpacity(0.3),
                                                  width: 1,
                                                ),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.check_circle,
                                                    color: Colors.white,
                                                    size: 14,
                                                  ),
                                                  SizedBox(width: 6),
                                                  Text(
                                                    'Completed',
                                                    style: TextStyle(
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
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                _formatDate(completedAt),
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
                                                child: Icon(
                                                  isExpanded 
                                                      ? Icons.keyboard_arrow_up_rounded
                                                      : Icons.keyboard_arrow_down_rounded,
                                                  color: Colors.white,
                                                  size: 24,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        
                                        const SizedBox(height: 12),
                                        
                                        // User Info Row
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
                                                  userName.isNotEmpty
                                                      ? userName[0].toUpperCase()
                                                      : '?',
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
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    userName,
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
                                                        padding: const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 3,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: Colors.white.withOpacity(0.1),
                                                          borderRadius: BorderRadius.circular(12),
                                                          border: Border.all(
                                                            color: Colors.white.withOpacity(0.3),
                                                            width: 1,
                                                          ),
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
                                                              'By: $responderName',
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                color: Colors.white.withOpacity(0.9),
                                                                fontWeight: FontWeight.w500,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 3,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: Colors.white.withOpacity(0.15),
                                                          borderRadius: BorderRadius.circular(12),
                                                          border: Border.all(
                                                            color: Colors.white.withOpacity(0.3),
                                                            width: 1,
                                                          ),
                                                        ),
                                                        child: Text(
                                                          responderType,
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: Colors.white.withOpacity(0.9),
                                                            fontWeight: FontWeight.w500,
                                                          ),
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
                                          crossFadeState: isExpanded 
                                              ? CrossFadeState.showSecond 
                                              : CrossFadeState.showFirst,
                                          firstChild: const SizedBox.shrink(),
                                          secondChild: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const SizedBox(height: 12),
                                              Container(
                                                height: 1,
                                                color: Colors.white.withOpacity(0.2),
                                              ),
                                              const SizedBox(height: 12),
                                              
                                              // ============================================================
                                              // COMPLETION TIME - GREEN THEMED CONTAINER
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
                                                      totalTime,
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
                                                value: userUid,
                                                isCopyable: true,
                                                copyValue: userUid,
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
                                              
                                              if (userPhone.isNotEmpty && userPhone != 'N/A')
                                                _buildTwoColumnInfoRow(
                                                  label: 'User Phone:',
                                                  value: userPhone,
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
                                                value: sosTime,
                                              ),
                                              
                                              // ✅ RESOLVED TIME - NOW FORMATTED PROPERLY
                                              _buildTwoColumnInfoRow(
                                                label: 'Resolved Time:',
                                                value: completedAt.isNotEmpty 
                                                    ? _getFormattedDateTime(completedAt)
                                                    : 'In Progress',
                                              ),
                                              
                                              _buildTwoColumnInfoRow(
                                                label: 'Distance:',
                                                value: distance.isNotEmpty ? distance : '0 km',
                                              ),
                                              
                                              if (emergencyDescription.isNotEmpty) ...[
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
                                                          emergencyDescription,
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
                            },
                          ),
                        ),
                ),
              ],
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
}