import 'package:dreambook/core/models/milestone_achievement.dart';
import 'package:dreambook/features/milestone/data/milestone_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'milestone_repository.dart' show milestoneRepositoryProvider;

final milestoneAchievementsProvider =
    FutureProvider.family<List<MilestoneAchievement>, String>(
  (ref, babyId) async {
    return ref.watch(milestoneRepositoryProvider).allForBaby(babyId);
  },
);
