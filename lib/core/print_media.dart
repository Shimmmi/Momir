import 'ble/printer_profile.dart';
import 'constants.dart';

/// Paper loaded in the XP-365B. Roll is the original receipt layout.
enum PrintMedia {
  roll57,
  label40x58;

  static PrintMedia fromName(String? name) {
    for (final media in values) {
      if (media.name == name) return media;
    }
    return PrintMedia.roll57;
  }

  String get title => switch (this) {
    PrintMedia.roll57 => 'Рулон 57 мм',
    PrintMedia.label40x58 => 'Этикетка 40×58',
  };

  int get widthDots => switch (this) {
    PrintMedia.roll57 => PrinterProfile.xp365b.printWidth,
    PrintMedia.label40x58 => kLabelWidthDots,
  };

  int get paperWidthMm => switch (this) {
    PrintMedia.roll57 => 48,
    PrintMedia.label40x58 => 40,
  };

  /// Die-cut labels have a fixed length. Roll height follows the bitmap.
  int? get paperHeightMm => switch (this) {
    PrintMedia.roll57 => null,
    PrintMedia.label40x58 => 58,
  };

  double get gapMm => switch (this) {
    PrintMedia.roll57 => 0,
    PrintMedia.label40x58 => kLabelGapMm,
  };

  bool get showsArt => this == PrintMedia.roll57;
}
