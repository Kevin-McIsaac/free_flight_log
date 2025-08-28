import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('cesium_terrain_enabled', true);
  print('Terrain enabled successfully!');
  print('Current terrain setting: ${prefs.getBool('cesium_terrain_enabled')}');
}