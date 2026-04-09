package me.jappie.haskellmobile;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothManager;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanResult;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.Manifest;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.View;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.EditText;

/**
 * Base Activity that wires up all haskell-mobile JNI boilerplate.
 * Consumer apps extend this class instead of copy-pasting the native
 * declarations, lifecycle forwarding, permission handling, etc.
 *
 * JNI native method resolution uses the declaring class for symbol names,
 * so these native methods always resolve to
 * Java_me_jappie_haskellmobile_HaskellMobileActivity_* regardless of
 * which subclass the runtime object is.
 */
public class HaskellMobileActivity extends Activity implements View.OnClickListener {

    static {
        System.loadLibrary("haskellmobile");
    }

    private native String greet(String name);
    private native void renderUI();
    private native void onButtonClick(View view);
    private native void onTextChange(View view, String text);
    private native void onLifecycleCreate();
    private native void onLifecycleStart();
    private native void onLifecycleResume();
    private native void onLifecyclePause();
    private native void onLifecycleStop();
    private native void onLifecycleDestroy();
    private native void onLifecycleLowMemory();
    private native void onPermissionResult(int requestCode, int statusCode);
    private native void onSecureStorageResult(int requestId, int statusCode, String value);
    private native void onBleScanResult(String deviceName, String deviceAddress, int rssi);
    private native void onDialogResult(int requestId, int actionCode);
    private native void onLocationResult(double lat, double lon, double alt, double acc);

    private static final String SECURE_PREFS_NAME = "haskell_mobile_secure_storage";

    private BluetoothLeScanner bleScanner;
    private ScanCallback bleScanCallback;

    private LocationManager locationManager;
    private LocationListener locationListener;

    /**
     * Map a permission code (from PermissionBridge.h) to an Android permission string.
     * Must match the PERMISSION_* constants in the C header.
     */
    private String permissionCodeToString(int permissionCode) {
        switch (permissionCode) {
            case 0: return Manifest.permission.ACCESS_FINE_LOCATION;
            case 1: return Manifest.permission.BLUETOOTH_SCAN;
            case 2: return Manifest.permission.CAMERA;
            case 3: return Manifest.permission.RECORD_AUDIO;
            case 4: return Manifest.permission.READ_CONTACTS;
            case 5: return Manifest.permission.READ_EXTERNAL_STORAGE;
            default: return null;
        }
    }

    /**
     * Request a runtime permission. Called from native code via JNI.
     * permissionCode: one of PERMISSION_* constants from PermissionBridge.h.
     * requestId: opaque ID passed back in the result callback.
     */
    public void requestPermission(int permissionCode, int requestId) {
        String permission = permissionCodeToString(permissionCode);
        if (permission == null) {
            onPermissionResult(requestId, 1); // PERMISSION_DENIED
            return;
        }
        if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            onPermissionResult(requestId, 0); // PERMISSION_GRANTED
            return;
        }
        requestPermissions(new String[]{ permission }, requestId);
    }

    /**
     * Check whether a permission is currently granted. Called from native code via JNI.
     * Returns 0 (PERMISSION_GRANTED) or 1 (PERMISSION_DENIED).
     */
    public int checkPermission(int permissionCode) {
        String permission = permissionCodeToString(permissionCode);
        if (permission == null) return 1;
        return checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED ? 0 : 1;
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        int statusCode = (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) ? 0 : 1;
        onPermissionResult(requestCode, statusCode);
    }

    /**
     * Write a key-value pair to secure storage. Called from native code via JNI.
     * Uses SharedPreferences with MODE_PRIVATE.
     */
    public void secureStorageWrite(int requestId, String key, String value) {
        try {
            SharedPreferences prefs = getSharedPreferences(SECURE_PREFS_NAME, Context.MODE_PRIVATE);
            prefs.edit().putString(key, value).apply();
            onSecureStorageResult(requestId, 0 /* SUCCESS */, null);
        } catch (Exception e) {
            onSecureStorageResult(requestId, 2 /* ERROR */, null);
        }
    }

    /**
     * Read a value from secure storage by key. Called from native code via JNI.
     * Returns SUCCESS with value if found, NOT_FOUND if absent.
     */
    public void secureStorageRead(int requestId, String key) {
        try {
            SharedPreferences prefs = getSharedPreferences(SECURE_PREFS_NAME, Context.MODE_PRIVATE);
            String value = prefs.getString(key, null);
            if (value != null) {
                onSecureStorageResult(requestId, 0 /* SUCCESS */, value);
            } else {
                onSecureStorageResult(requestId, 1 /* NOT_FOUND */, null);
            }
        } catch (Exception e) {
            onSecureStorageResult(requestId, 2 /* ERROR */, null);
        }
    }

    /**
     * Delete a key from secure storage. Called from native code via JNI.
     */
    public void secureStorageDelete(int requestId, String key) {
        try {
            SharedPreferences prefs = getSharedPreferences(SECURE_PREFS_NAME, Context.MODE_PRIVATE);
            prefs.edit().remove(key).apply();
            onSecureStorageResult(requestId, 0 /* SUCCESS */, null);
        } catch (Exception e) {
            onSecureStorageResult(requestId, 2 /* ERROR */, null);
        }
    }

    /**
     * Check the BLE adapter status. Called from native code via JNI.
     * Returns BLE_ADAPTER_ON (1), BLE_ADAPTER_OFF (0),
     * BLE_ADAPTER_UNAUTHORIZED (2), or BLE_ADAPTER_UNSUPPORTED (3).
     */
    public int checkBleAdapter() {
        try {
            if (!getPackageManager().hasSystemFeature(android.content.pm.PackageManager.FEATURE_BLUETOOTH_LE)) {
                return 3; // BLE_ADAPTER_UNSUPPORTED
            }
            BluetoothManager manager = (BluetoothManager) getSystemService(Context.BLUETOOTH_SERVICE);
            if (manager == null) {
                return 3; // BLE_ADAPTER_UNSUPPORTED
            }
            BluetoothAdapter adapter = manager.getAdapter();
            if (adapter == null) {
                return 3; // BLE_ADAPTER_UNSUPPORTED
            }
            if (!adapter.isEnabled()) {
                return 0; // BLE_ADAPTER_OFF
            }
            return 1; // BLE_ADAPTER_ON
        } catch (Exception e) {
            android.util.Log.e("BleBridge", "checkBleAdapter failed: " + e.getMessage());
            return 3; // BLE_ADAPTER_UNSUPPORTED
        }
    }

    /**
     * Start a BLE scan. Called from native code via JNI.
     * Scan results are delivered via onBleScanResult JNI callback.
     */
    public void startBleScan() {
        try {
            BluetoothManager manager = (BluetoothManager) getSystemService(Context.BLUETOOTH_SERVICE);
            if (manager == null) return;
            BluetoothAdapter adapter = manager.getAdapter();
            if (adapter == null || !adapter.isEnabled()) return;

            bleScanner = adapter.getBluetoothLeScanner();
            if (bleScanner == null) return;

            bleScanCallback = new ScanCallback() {
                @Override
                public void onScanResult(int callbackType, ScanResult result) {
                    String name = result.getDevice().getName();
                    String address = result.getDevice().getAddress();
                    int rssi = result.getRssi();
                    onBleScanResult(name, address, rssi);
                }
            };

            bleScanner.startScan(bleScanCallback);
        } catch (Exception e) {
            android.util.Log.e("BleBridge", "startBleScan failed: " + e.getMessage());
        }
    }

    /**
     * Stop a running BLE scan. Called from native code via JNI.
     */
    public void stopBleScan() {
        try {
            if (bleScanner != null && bleScanCallback != null) {
                bleScanner.stopScan(bleScanCallback);
                bleScanCallback = null;
            }
        } catch (Exception e) {
            android.util.Log.e("BleBridge", "stopBleScan failed: " + e.getMessage());
        }
    }

    /**
     * Show a modal dialog with up to 3 buttons. Called from native code via JNI.
     * requestId: opaque ID passed back in the result callback.
     * title: dialog title.
     * message: dialog message.
     * btn1: label for button 1 (always present).
     * btn2: label for button 2, or null to omit.
     * btn3: label for button 3, or null to omit.
     */
    public void showDialog(final int requestId, String title, String message,
                           String btn1, String btn2, String btn3) {
        final boolean[] buttonPressed = {false};

        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle(title);
        builder.setMessage(message);

        builder.setPositiveButton(btn1, new DialogInterface.OnClickListener() {
            @Override
            public void onClick(DialogInterface dialog, int which) {
                buttonPressed[0] = true;
                onDialogResult(requestId, 0); // DIALOG_BUTTON_1
            }
        });

        if (btn2 != null) {
            builder.setNegativeButton(btn2, new DialogInterface.OnClickListener() {
                @Override
                public void onClick(DialogInterface dialog, int which) {
                    buttonPressed[0] = true;
                    onDialogResult(requestId, 1); // DIALOG_BUTTON_2
                }
            });
        }

        if (btn3 != null) {
            builder.setNeutralButton(btn3, new DialogInterface.OnClickListener() {
                @Override
                public void onClick(DialogInterface dialog, int which) {
                    buttonPressed[0] = true;
                    onDialogResult(requestId, 2); // DIALOG_BUTTON_3
                }
            });
        }

        builder.setOnDismissListener(new DialogInterface.OnDismissListener() {
            @Override
            public void onDismiss(DialogInterface dialog) {
                if (!buttonPressed[0]) {
                    onDialogResult(requestId, 3); // DIALOG_DISMISSED
                }
            }
        });

        builder.show();
    }

    /**
     * Start receiving GPS location updates. Called from native code via JNI.
     * Uses LocationManager (AOSP built-in) with GPS_PROVIDER.
     * Updates are delivered via onLocationResult JNI callback.
     */
    public void startLocationUpdates() {
        try {
            locationManager = (LocationManager) getSystemService(Context.LOCATION_SERVICE);
            if (locationManager == null) {
                android.util.Log.e("LocationBridge", "LocationManager unavailable");
                return;
            }

            locationListener = new LocationListener() {
                @Override
                public void onLocationChanged(Location location) {
                    onLocationResult(
                        location.getLatitude(),
                        location.getLongitude(),
                        location.getAltitude(),
                        location.getAccuracy()
                    );
                }

                @Override
                public void onProviderEnabled(String provider) {}

                @Override
                public void onProviderDisabled(String provider) {}

                @Override
                public void onStatusChanged(String provider, int status, Bundle extras) {}
            };

            locationManager.requestLocationUpdates(
                LocationManager.GPS_PROVIDER, 1000, 0, locationListener);
        } catch (SecurityException e) {
            android.util.Log.e("LocationBridge",
                "startLocationUpdates: permission denied: " + e.getMessage());
        } catch (Exception e) {
            android.util.Log.e("LocationBridge",
                "startLocationUpdates failed: " + e.getMessage());
        }
    }

    /**
     * Stop receiving GPS location updates. Called from native code via JNI.
     */
    public void stopLocationUpdates() {
        try {
            if (locationManager != null && locationListener != null) {
                locationManager.removeUpdates(locationListener);
                locationListener = null;
            }
        } catch (Exception e) {
            android.util.Log.e("LocationBridge",
                "stopLocationUpdates failed: " + e.getMessage());
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        onLifecycleCreate();
        // Render UI from Haskell instead of XML layout
        renderUI();
    }

    @Override
    public void onClick(View v) {
        onButtonClick(v);
    }

    /**
     * Register a WebViewClient on a WebView. Called from native code
     * when a WebView widget has an EventClick (page-load) handler.
     * The client fires onButtonClick when a page finishes loading.
     */
    public void registerWebViewClient(final WebView webView) {
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageFinished(WebView view, String url) {
                onButtonClick(view);
            }
        });
    }

    /**
     * Register a TextWatcher on an EditText. Called from native code
     * when a TextInput widget has an EventTextChange handler.
     * The watcher forwards text changes to the native onTextChange method.
     */
    public void registerTextWatcher(final EditText editText) {
        editText.addTextChangedListener(new TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {}

            @Override
            public void onTextChanged(CharSequence s, int start, int before, int count) {}

            @Override
            public void afterTextChanged(Editable s) {
                onTextChange(editText, s.toString());
            }
        });
    }

    @Override
    protected void onStart() {
        super.onStart();
        onLifecycleStart();
    }

    @Override
    protected void onResume() {
        super.onResume();
        onLifecycleResume();
    }

    @Override
    protected void onPause() {
        super.onPause();
        onLifecyclePause();
    }

    @Override
    protected void onStop() {
        super.onStop();
        onLifecycleStop();
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        onLifecycleDestroy();
    }

    @Override
    public void onLowMemory() {
        super.onLowMemory();
        onLifecycleLowMemory();
    }
}
