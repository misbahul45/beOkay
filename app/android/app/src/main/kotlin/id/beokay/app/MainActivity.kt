package id.beokay.app

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// Health Connect meminta izin lewat Activity Result API, sehingga butuh FragmentActivity.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        HealthMetadataBridge(applicationContext).register(flutterEngine)
    }
}
