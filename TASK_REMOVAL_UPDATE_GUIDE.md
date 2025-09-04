# Flutter App Update Guide - Task Removal

## Overview
The backend no longer supports tasks. League promotion is now purely based on carbon savings. This guide shows what needs to be updated in the Flutter app.

## Files to Update

### 1. **lib/models/user_progress.dart**
Remove all task-related code:
- Remove `TaskProgress` class entirely
- Remove `TaskType` enum
- Remove `LeagueRequirements` class
- Update `UserProgress` class:
  ```dart
  class UserProgress {
    final String currentLeague;
    final double? lastMonthCarbonSaved;
    final DateTime? lastCalculationDate;
    final DateTime lastUpdated;
    final bool shouldShowLeagueUpgrade;

    UserProgress({
      required this.currentLeague,
      this.lastMonthCarbonSaved,
      this.lastCalculationDate,
      required this.lastUpdated,
      this.shouldShowLeagueUpgrade = false,
    });

    factory UserProgress.fromJson(Map<String, dynamic> json) {
      return UserProgress(
        currentLeague: json['current_league'] ?? 'bronze',
        lastMonthCarbonSaved: json['last_month_co2e_saved_g']?.toDouble(),
        lastCalculationDate: json['last_calculation_date'] != null
            ? DateTime.parse(json['last_calculation_date'])
            : null,
        lastUpdated: DateTime.now(),
        shouldShowLeagueUpgrade: json['should_show_league_upgrade'] ?? false,
      );
    }
  }
  ```

### 2. **lib/services/user_progress_service.dart**
Major updates needed:
- Remove `completeTask()` method
- Remove `_checkAndCompleteTasks()` method
- Update `getUserProgress()` to not fetch tasks:
  ```dart
  Future<UserProgress> getUserProgress() async {
    try {
      final progressResponse = await _apiService.get('/progress/summary');
      final progressData = progressResponse.data as Map<String, dynamic>;
      
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
    } catch (e) {
      // Return default if API fails
      return UserProgress(
        currentLeague: 'bronze',
        lastMonthCarbonSaved: null,
        lastCalculationDate: null,
        lastUpdated: DateTime.now(),
      );
    }
  }
  ```
- Remove task checking from `trackAppOpen()`, `trackUsageLog()`, and `trackLogin()`

### 3. **lib/screens/dashboard_screen.dart**
Remove any UI that displays tasks. Look for:
- Task progress indicators
- Task completion checkmarks
- Task lists or cards

### 4. **lib/widgets/league_upgrade_success_popup.dart**
Update to show carbon-based requirements instead of tasks:
```dart
// Old: "Complete 3 tasks to advance"
// New: "Save XXXg CO2e to advance to next league"

// League thresholds:
// Bronze → Silver: 100g CO2e
// Silver → Gold: 500g CO2e  
// Gold → Emerald: 700g CO2e
// Emerald → Diamond: 1000g CO2e
```

### 5. **Remove API Calls**
Search and remove any references to:
- `/api/v1/tasks`
- `/api/v1/tasks/my-tasks`
- `/api/v1/tasks/complete/`
- `/api/v1/progress/tasks`

### 6. **Update Progress Display**
Show carbon-based progression:
```dart
// Example progress widget
Text('Carbon saved this month: ${currentMonthCarbonSaved}g CO2e'),
Text('Next league requirement: ${getRequirementForNextLeague(currentLeague)}g CO2e'),
LinearProgressIndicator(
  value: currentMonthCarbonSaved / getRequirementForNextLeague(currentLeague),
),
```

## New League Promotion Display Logic

```dart
double getRequirementForNextLeague(String currentLeague) {
  switch (currentLeague) {
    case 'bronze':
      return 100.0;
    case 'silver':
      return 500.0;
    case 'gold':
      return 700.0;
    case 'emerald':
      return 1000.0;
    case 'diamond':
      return double.infinity; // Max level
    default:
      return 100.0;
  }
}

String getNextLeague(String currentLeague) {
  switch (currentLeague) {
    case 'bronze':
      return 'silver';
    case 'silver':
      return 'gold';
    case 'gold':
      return 'emerald';
    case 'emerald':
      return 'diamond';
    case 'diamond':
      return 'diamond'; // Max level
    default:
      return 'bronze';
  }
}
```

## Testing Checklist
1. [ ] App loads without task-related errors
2. [ ] Progress screen shows carbon savings
3. [ ] No task UI elements visible
4. [ ] League promotion based on carbon works
5. [ ] No network errors from removed endpoints

## Benefits
- Simpler, clearer progression system
- Users focus on one metric: carbon saved
- Less confusing UI
- Easier to understand advancement requirements