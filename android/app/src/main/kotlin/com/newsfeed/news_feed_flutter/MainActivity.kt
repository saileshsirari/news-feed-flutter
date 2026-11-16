package com.newsfeed.news_feed_flutter

import io.flutter.embedding.android.FlutterFragmentActivity

// A FlutterFragmentActivity, not a FlutterActivity: Stripe's payment sheet
// (taxi fares and tickets paid in euros or dollars) is built from Android
// fragments, so it needs an activity that can host them.
class MainActivity : FlutterFragmentActivity()
