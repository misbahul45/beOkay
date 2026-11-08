import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../consent/application/consent_controller.dart';
import '../../preferences/application/preferences_controller.dart';
import '../data/nutrition_models.dart';
import '../data/nutrition_repository.dart';

final nutritionRepositoryProvider=Provider<NutritionRepository>((ref){
  final auth=ref.watch(authControllerProvider);
  final id=auth is AuthAuthenticated?auth.user.id:null;
  return NutritionRepository(ref.watch(apiClientProvider),isCurrentAccount:(){if(!ref.mounted)return false;final current=ref.read(authControllerProvider);return id!=null&&current is AuthAuthenticated&&current.user.id==id;});
});
final mealProvider=FutureProvider.autoDispose.family<MealRecord,String>((ref,id)async{
  final repo=ref.watch(nutritionRepositoryProvider);
  final consent=ref.watch(consentControllerProvider.future);
  final prefs=ref.watch(preferencesControllerProvider.future);
  await Future.wait([consent,prefs]);return repo.get(id);
});
