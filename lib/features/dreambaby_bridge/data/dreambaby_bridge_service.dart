import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

class DreamBabyBridgeService {
  static const _dreamBabyAndroidUri =
      'intent:#Intent;package=com.dreambaby.dreambaby;end';
  static const _playStoreUri =
      'https://play.google.com/store/apps/details?id=com.dreambaby.dreambaby';

  // Returns true if DreamBaby is installed on this device.
  Future<bool> isInstalled() async {
    try {
      return await canLaunchUrl(Uri.parse(_dreamBabyAndroidUri));
    } catch (_) {
      return false;
    }
  }

  // Launches DreamBaby if installed, otherwise opens the Play Store listing.
  Future<void> launch() async {
    final installed = await isInstalled();
    final uri = Uri.parse(installed ? _dreamBabyAndroidUri : _playStoreUri);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

final dreamBabyBridgeServiceProvider =
    Provider<DreamBabyBridgeService>((_) => DreamBabyBridgeService());

final dreamBabyInstalledProvider = FutureProvider<bool>((ref) {
  return ref.watch(dreamBabyBridgeServiceProvider).isInstalled();
});
