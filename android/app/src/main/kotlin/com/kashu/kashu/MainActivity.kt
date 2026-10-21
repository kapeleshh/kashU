package com.kashu.kashu

import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth shows the system BiometricPrompt, which needs a FragmentActivity:
// with a plain FlutterActivity every authenticate() call fails with
// `no_fragment_activity`, so an enabled app lock could never be unlocked.
class MainActivity : FlutterFragmentActivity()
