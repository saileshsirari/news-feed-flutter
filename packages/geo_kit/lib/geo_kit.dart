/// Points, distances, the device's (rounded) location, a map, and a place
/// picker: everything "near me" needs on the phone, for this app and any
/// later one (nearby places, rides). No server in here: an app passes its
/// own [PlaceSearch].
library;

export 'src/geo_point.dart';
export 'src/my_location.dart';
export 'src/place.dart';
export 'src/place_map.dart';
export 'src/place_picker.dart';
