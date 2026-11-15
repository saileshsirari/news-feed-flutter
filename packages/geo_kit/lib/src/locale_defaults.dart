import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/widgets.dart' show WidgetsBinding;

import 'geo_point.dart';

/// The device's language and region ("en-IN"), as Flutter sees it (so a
/// widget test can set it), or straight from the platform before Flutter
/// has started.
Locale deviceLocale() {
  try {
    return WidgetsBinding.instance.platformDispatcher.locale;
  } on Object {
    return PlatformDispatcher.instance.locale;
  }
}

/// How far things are shown: kilometres for most of the world, miles where
/// road signs use them (the USA, the UK, Liberia, Myanmar).
enum DistanceUnit {
  km,
  miles;

  static const _milesCountries = {'US', 'GB', 'LR', 'MM'};

  /// From a locale's country ("en_US" -> miles, "en_IN" -> km). A locale
  /// with no country ("en") gets km, the world's default.
  static DistanceUnit forLocale(Locale locale) =>
      _milesCountries.contains(locale.countryCode?.toUpperCase()) ? miles : km;

  /// From the device's own language and region settings.
  static DistanceUnit get device => forLocale(deviceLocale());
}

/// Where a map opens when there's nothing better to go on (no saved place,
/// no rough location): the middle of the device's country, zoomed out to
/// show it, or the whole world for a country not listed.
///
/// Like a paper map shop handing you the map of your own country first.
({GeoPoint center, double zoom}) defaultMapView([Locale? locale]) {
  final country = (locale ?? deviceLocale()).countryCode?.toUpperCase();
  return _countryViews[country] ?? (center: const GeoPoint(20, 0), zoom: 2);
}

/// A handful of countries the app is used in; others get the world view.
/// (Big countries are zoomed out further: all of India or the USA in view.)
const _countryViews = <String, ({GeoPoint center, double zoom})>{
  // India: Delhi, zoomed out enough to see most of the country.
  'IN': (center: GeoPoint(28.61, 77.21), zoom: 5),
  'US': (center: GeoPoint(39.83, -98.58), zoom: 4),
  'CA': (center: GeoPoint(45.42, -75.70), zoom: 4),
  'GB': (center: GeoPoint(51.51, -0.13), zoom: 6),
  'IE': (center: GeoPoint(53.35, -6.26), zoom: 6),
  'DE': (center: GeoPoint(51.16, 10.45), zoom: 6),
  'FR': (center: GeoPoint(46.60, 2.35), zoom: 6),
  'ES': (center: GeoPoint(40.42, -3.70), zoom: 6),
  'IT': (center: GeoPoint(42.50, 12.50), zoom: 6),
  'NL': (center: GeoPoint(52.37, 4.90), zoom: 7),
  'BE': (center: GeoPoint(50.85, 4.35), zoom: 7),
  'PT': (center: GeoPoint(39.40, -8.22), zoom: 6),
  'SE': (center: GeoPoint(59.33, 18.07), zoom: 5),
  'PL': (center: GeoPoint(52.23, 21.01), zoom: 6),
  'CH': (center: GeoPoint(46.95, 7.45), zoom: 7),
  'AT': (center: GeoPoint(48.21, 16.37), zoom: 7),
  'AE': (center: GeoPoint(25.20, 55.27), zoom: 7),
  'SG': (center: GeoPoint(1.35, 103.82), zoom: 11),
  'AU': (center: GeoPoint(-25.27, 133.78), zoom: 4),
};
