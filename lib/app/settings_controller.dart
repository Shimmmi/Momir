import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../core/print_media.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._prefs) {
    rerollEnabled = _prefs.getBool(kPrefsReroll) ?? true;
    final raw = _prefs.getStringList(kPrefsColorFilter) ?? const [];
    colorFilter = raw.toSet();
    printMedia = PrintMedia.fromName(_prefs.getString(kPrefsPrintMedia));
  }

  final SharedPreferences _prefs;

  var rerollEnabled = true;
  Set<String> colorFilter = {};
  PrintMedia printMedia = PrintMedia.roll57;

  Future<void> setReroll(bool value) async {
    rerollEnabled = value;
    await _prefs.setBool(kPrefsReroll, value);
    notifyListeners();
  }

  Future<void> toggleColor(String color) async {
    if (colorFilter.contains(color)) {
      colorFilter.remove(color);
    } else {
      colorFilter.add(color);
    }
    colorFilter = {...colorFilter};
    await _prefs.setStringList(kPrefsColorFilter, colorFilter.toList());
    notifyListeners();
  }

  Future<void> clearColors() async {
    colorFilter = {};
    await _prefs.setStringList(kPrefsColorFilter, const []);
    notifyListeners();
  }

  Future<void> setPrintMedia(PrintMedia value) async {
    printMedia = value;
    await _prefs.setString(kPrefsPrintMedia, value.name);
    notifyListeners();
  }
}
