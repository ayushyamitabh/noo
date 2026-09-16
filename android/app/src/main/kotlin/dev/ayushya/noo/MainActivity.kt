package dev.ayushya.noo

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not the default FlutterActivity) is required by
// local_auth's Android implementation, which hosts its biometric/device
// credential prompt via a Fragment.
class MainActivity : FlutterFragmentActivity()
