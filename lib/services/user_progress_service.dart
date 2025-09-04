import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/user_progress.dart';
import '../models/usage_metrics.dart';
import '../services/api_service.dart';

class UserProgressService {
  static const String _metricsKey = 'usage_metrics';
  static const String _leagueUpgradeShownKey = 'league_upgrade_shown';
  static const String _previousLeagueKey = 'previous_league';
  
  final ApiService _apiService = ApiService();
  
  // Getter for API service
  ApiService get apiService => _apiService;

  // Get current user progress from API
  Future<UserProgress> getUserProgress() async {
    try {
      // Get progress summary from API
      final progressResponse = await _apiService.get('/progress/summary');
      print('Progress response data: ${progressResponse.data}');
      print('🔍 API Response - should_show_league_upgrade: ${progressResponse.data['should_show_league_upgrade']}');
      
      // Safely access fields with null checks
      final progressData = progressResponse.data as Map<String, dynamic>;
      
      // Before returning, save the current league
      await savePreviousLeague(progressData['current_league'] ?? 'bronze');
      
      return UserProgress(
        currentLeague: progressData['current_league'] ?? 'bronze',
        lastMonthCarbonSaved: progressData['last_month_co2e_saved_g']?.toDouble(),
        lastCalculationDate: progressData['last_calculation_date'] != null
            ? DateTime.parse(progressData['last_calculation_date'])
            : null,
        lastUpdated: DateTime.now(),
        shouldShowLeagueUpgrade: progressData['should_show_league_upgrade'] ?? false,
      );
    } catch (e, stackTrace) {
      print('Error fetching user progress: $e');
      print('Stack trace: $stackTrace');
      // Return default if API fails
      return UserProgress(
        currentLeague: 'bronze',
        lastMonthCarbonSaved: null,
        lastCalculationDate: null,
        lastUpdated: DateTime.now(),
      );
    }
  }


  // Get usage metrics (still stored locally for UI performance)
  Future<UsageMetrics> getUsageMetrics() async {
    final prefs = await SharedPreferences.getInstance();
    final metricsString = prefs.getString(_metricsKey);
    
    if (metricsString != null) {
      final json = jsonDecode(metricsString);
      return UsageMetrics.fromJson(json);
    }
    
    return UsageMetrics.empty();
  }

  // Save usage metrics locally
  Future<void> saveUsageMetrics(UsageMetrics metrics) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_metricsKey, jsonEncode(metrics.toJson()));
  }

  // Track app open and check tasks
  Future<void> trackAppOpen() async {
    final metrics = await getUsageMetrics();
    final now = DateTime.now();
    
    // Update local metrics
    final updatedMetrics = metrics.copyWith(
      totalAppOpens: metrics.totalAppOpens + 1,
      monthlyAppOpens: _isCurrentMonth(metrics.lastAppOpen) 
          ? metrics.monthlyAppOpens + 1 
          : 1,
      weeklyAppOpens: _isCurrentWeek(metrics.lastAppOpen)
          ? metrics.weeklyAppOpens + 1
          : 1,
      dailyAppOpens: _isToday(metrics.lastAppOpen)
          ? metrics.dailyAppOpens + 1
          : 1,
      firstAppOpen: metrics.firstAppOpen ?? now,
      lastAppOpen: now,
      dailyOpenTimestamps: _updateDailyTimestamps(
        metrics.dailyOpenTimestamps, 
        now,
      ),
    );
    
    await saveUsageMetrics(updatedMetrics);
  }

  // Track appliance usage log
  Future<void> trackUsageLog(String applianceType, double carbonSaved) async {
    final metrics = await getUsageMetrics();
    final now = DateTime.now();
    
    final updatedAppliances = Set<String>.from(metrics.appliancesUsed)
      ..add(applianceType);
    
    final updatedMetrics = metrics.copyWith(
      totalLogs: metrics.totalLogs + 1,
      monthlyLogs: _isCurrentMonth(now) ? metrics.monthlyLogs + 1 : 1,
      weeklyLogs: _isCurrentWeek(now) ? metrics.weeklyLogs + 1 : 1,
      dailyLogs: _isToday(now) ? metrics.dailyLogs + 1 : 1,
      appliancesUsed: updatedAppliances,
      totalCarbonSaved: metrics.totalCarbonSaved + carbonSaved,
      monthlyCarbonSaved: _isCurrentMonth(now)
          ? metrics.monthlyCarbonSaved + carbonSaved
          : carbonSaved,
      firstLog: metrics.firstLog ?? now,
      dailyLogTimestamps: _updateDailyTimestamps(
        metrics.dailyLogTimestamps,
        now,
      ),
    );
    
    await saveUsageMetrics(updatedMetrics);
  }

  // Track user login
  Future<void> trackLogin() async {
    final metrics = await getUsageMetrics();
    final now = DateTime.now();
    
    if (metrics.firstLogin == null) {
      final updatedMetrics = metrics.copyWith(firstLogin: now);
      await saveUsageMetrics(updatedMetrics);
    }
  }


  // Clear all progress data (for testing/debugging)
  Future<void> clearAllProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_metricsKey);
    await prefs.remove(_leagueUpgradeShownKey);
    print('🧹 All progress data cleared');
  }

  // Initialize progress for new user
  Future<void> initializeNewUserProgress() async {
    await clearAllProgress();
    
    final now = DateTime.now();
    
    // Create fresh metrics for new user
    final freshMetrics = UsageMetrics(
      totalAppOpens: 1,
      monthlyAppOpens: 1,
      weeklyAppOpens: 1,
      dailyAppOpens: 1,
      totalLogs: 0,
      monthlyLogs: 0,
      weeklyLogs: 0,
      dailyLogs: 0,
      appliancesUsed: {},
      totalCarbonSaved: 0,
      monthlyCarbonSaved: 0,
      firstAppOpen: now,
      firstLogin: now,
      firstLog: null,
      lastAppOpen: now,
      dailyOpenTimestamps: [now],
      dailyLogTimestamps: [],
    );
    
    await saveUsageMetrics(freshMetrics);
  }

  // Check if league upgrade animation should be shown
  Future<bool> shouldShowLeagueUpgrade() async {
    try {
      final response = await _apiService.get('/progress/summary');
      return response.data['should_show_league_upgrade'] ?? false;
    } catch (e) {
      return false;
    }
  }

  // Mark league upgrade as shown
  Future<void> markLeagueUpgradeShown() async {
    try {
      await _apiService.post('/progress/mark-league-upgrade-shown');
    } catch (e) {
      print('Error marking league upgrade as shown: $e');
    }
  }

  // Helper methods
  bool _isCurrentMonth(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month;
  }

  bool _isCurrentWeek(DateTime date) {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    return date.isAfter(weekStart);
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  List<DateTime> _updateDailyTimestamps(
    List<DateTime> timestamps,
    DateTime newTimestamp,
  ) {
    final updated = List<DateTime>.from(timestamps)..add(newTimestamp);
    return updated.where((ts) => _isCurrentMonth(ts)).toList();
  }

  bool _hasOpenedEveryDay(List<DateTime> timestamps) {
    if (timestamps.isEmpty) return false;
    
    final now = DateTime.now();
    final currentDay = now.day;
    
    final uniqueDays = timestamps
        .map((ts) => ts.day)
        .toSet();
    
    for (int day = 1; day <= currentDay; day++) {
      if (!uniqueDays.contains(day)) {
        return false;
      }
    }
    
    return true;
  }

  bool _hasLoggedEveryDay(List<DateTime> timestamps) {
    return _hasOpenedEveryDay(timestamps);
  }

  // Get previous league from SharedPreferences
  Future<String?> getPreviousLeague() async {
    final prefs = await SharedPreferences.getInstance();
    final league = prefs.getString(_previousLeagueKey);
    print('📊 getPreviousLeague: $league');
    return league;
  }

  // Save previous league to SharedPreferences
  Future<void> savePreviousLeague(String league) async {
    final prefs = await SharedPreferences.getInstance();
    final previousLeague = await getPreviousLeague();
    print('📊 savePreviousLeague: $previousLeague -> $league');
    await prefs.setString(_previousLeagueKey, league);
  }
}