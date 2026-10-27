/// Shared geometry and motion values for the viewer presentation layer.
///
/// Keeping these values in one place prevents individual widgets from
/// gradually inventing slightly different spacing, hit targets and timings.
abstract final class AppTokens {
  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space5 = 24.0;
  static const space6 = 32.0;

  static const controlRadius = 4.0;
  static const menuRadius = 8.0;
  static const menuItemRadius = 4.0;
  static const menuItemHeight = 40.0;
  static const menuIconSize = 18.0;
  static const menuMaxWidth = 360.0;
  static const containerRadius = 8.0;
  static const dialogRadius = 8.0;
  static const dialogElevation = 16.0;
  static const iconButtonSize = 32.0;
  static const controlHeight = 36.0;
  static const primaryControlHeight = 40.0;
  static const dialogActionMinWidth = 104.0;
  static const switchWidth = 40.0;

  static const zoomSliderThumbRadius = 6.0;
  static const zoomSliderOverlayRadius = 9.0;
  static const thumbnailWidth = 96.0;
  static const thumbnailHeight = 72.0;
  static const thumbnailStep = 104.0;
  static const thumbnailRadius = 4.0;
  static const thumbnailLabelHeight = 22.0;

  static const panelAnimation = Duration(milliseconds: 180);
  static const selectionAnimation = Duration(milliseconds: 120);
  static const thumbnailScrollAnimation = Duration(milliseconds: 140);
}
