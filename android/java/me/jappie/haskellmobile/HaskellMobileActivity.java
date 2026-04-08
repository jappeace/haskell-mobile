package me.jappie.haskellmobile;

import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.Manifest;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.View;
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

    private static final String SECURE_PREFS_NAME = "haskell_mobile_secure_storage";

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
