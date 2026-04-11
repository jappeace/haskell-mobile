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
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.TotalCaptureResult;
import android.graphics.ImageFormat;
import android.graphics.SurfaceTexture;
import android.media.Image;
import android.media.ImageReader;
import android.media.MediaRecorder;
import android.net.Uri;
import android.os.Handler;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
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
    private native void onAuthSessionResult(int requestId, int statusCode,
                                             String redirectUrl, String errorMsg);
    private native void onCameraResult(int requestId, int statusCode,
                                       byte[] imageData, int width, int height);
    private native void onVideoFrame(int requestId, byte[] frameData, int width, int height);
    private native void onAudioChunk(int requestId, byte[] audioData);
    private native void onBottomSheetResult(int requestId, int actionCode);
    private native void onHttpResult(int requestId, int resultCode, int httpStatus,
                                      String headers, byte[] body);
    private native void onNetworkStatusChange(int connected, int transport);

    private static final String SECURE_PREFS_NAME = "haskell_mobile_secure_storage";

    private BluetoothLeScanner bleScanner;
    private ScanCallback bleScanCallback;

    private LocationManager locationManager;
    private LocationListener locationListener;

    private ConnectivityManager connectivityManager;
    private ConnectivityManager.NetworkCallback networkCallback;

    private int pendingAuthRequestId = -1;
    private boolean authRedirectReceived = false;

    private CameraDevice cameraDevice;
    private CameraCaptureSession cameraCaptureSession;
    private ImageReader imageReader;
    private ImageReader videoFrameReader;
    private android.media.AudioRecord audioRecord;
    private Thread audioRecordThread;
    private volatile boolean audioRecording;
    private int videoRequestId;

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
     * Show a bottom sheet / action menu. Called from native code via JNI.
     * requestId: opaque ID passed back in the result callback.
     * title: bottom sheet title.
     * items: newline-separated item labels.
     */
    public void showBottomSheet(final int requestId, String title, String items) {
        final boolean[] itemSelected = {false};
        String[] itemLabels = items.split("\n");

        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle(title);
        builder.setItems(itemLabels, new DialogInterface.OnClickListener() {
            @Override
            public void onClick(DialogInterface dialog, int which) {
                itemSelected[0] = true;
                onBottomSheetResult(requestId, which);
            }
        });
        builder.setOnDismissListener(new DialogInterface.OnDismissListener() {
            @Override
            public void onDismiss(DialogInterface dialog) {
                if (!itemSelected[0]) {
                    onBottomSheetResult(requestId, -1); // BOTTOM_SHEET_DISMISSED
                }
            }
        });
        builder.show();
    }

    /**
     * Perform an HTTP request on a background thread. Called from native code via JNI.
     * requestId: opaque ID passed back in the result callback.
     * method: 0=GET, 1=POST, 2=PUT, 3=DELETE.
     * url: request URL.
     * headers: newline-delimited "Key: Value\n" headers, or null.
     * body: request body bytes, or null.
     */
    public void httpRequest(final int requestId, final int method,
                            final String url, final String headers,
                            final byte[] body) {
        /* In autotest mode, return stub 200 success without making a real request.
         * CI emulators may not have network access to arbitrary hosts.
         * Pass --ez autotest true via am start to enable. */
        if (getIntent().getBooleanExtra("autotest", false)) {
            android.util.Log.i("HttpBridge", "http_request: autotest mode -- returning stub success");
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    onHttpResult(requestId, 0 /* SUCCESS */, 200,
                                 "Content-Type: text/plain\n", new byte[0]);
                }
            });
            return;
        }

        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    java.net.URL urlObj = new java.net.URL(url);
                    java.net.HttpURLConnection conn =
                        (java.net.HttpURLConnection) urlObj.openConnection();

                    String[] methodNames = {"GET", "POST", "PUT", "DELETE"};
                    String methodName = (method >= 0 && method < methodNames.length)
                        ? methodNames[method] : "GET";
                    conn.setRequestMethod(methodName);
                    conn.setConnectTimeout(30000);
                    conn.setReadTimeout(30000);

                    /* Set request headers */
                    if (headers != null) {
                        for (String line : headers.split("\n")) {
                            int colonIdx = line.indexOf(": ");
                            if (colonIdx > 0) {
                                String key = line.substring(0, colonIdx);
                                String value = line.substring(colonIdx + 2);
                                conn.setRequestProperty(key, value);
                            }
                        }
                    }

                    /* Write request body for POST/PUT */
                    if (body != null && body.length > 0
                        && (method == 1 || method == 2)) {
                        conn.setDoOutput(true);
                        conn.getOutputStream().write(body);
                        conn.getOutputStream().close();
                    }

                    final int httpStatus = conn.getResponseCode();

                    /* Read response headers */
                    StringBuilder respHeaders = new StringBuilder();
                    for (int i = 0; ; i++) {
                        String headerName = conn.getHeaderFieldKey(i);
                        String headerValue = conn.getHeaderField(i);
                        if (headerValue == null) break;
                        if (headerName != null) {
                            respHeaders.append(headerName)
                                       .append(": ")
                                       .append(headerValue)
                                       .append("\n");
                        }
                    }

                    /* Read response body */
                    java.io.InputStream inputStream;
                    try {
                        inputStream = conn.getInputStream();
                    } catch (java.io.IOException e) {
                        inputStream = conn.getErrorStream();
                    }
                    byte[] respBody = new byte[0];
                    if (inputStream != null) {
                        java.io.ByteArrayOutputStream baos =
                            new java.io.ByteArrayOutputStream();
                        byte[] buf = new byte[4096];
                        int bytesRead;
                        while ((bytesRead = inputStream.read(buf)) != -1) {
                            baos.write(buf, 0, bytesRead);
                        }
                        respBody = baos.toByteArray();
                        inputStream.close();
                    }

                    conn.disconnect();

                    final String finalHeaders = respHeaders.toString();
                    final byte[] finalBody = respBody;
                    runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            onHttpResult(requestId, 0 /* SUCCESS */,
                                         httpStatus, finalHeaders, finalBody);
                        }
                    });
                } catch (java.net.SocketTimeoutException e) {
                    runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            onHttpResult(requestId, 2 /* TIMEOUT */,
                                         0, null, null);
                        }
                    });
                } catch (final Exception e) {
                    final String errorMsg = e.getMessage();
                    runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            onHttpResult(requestId, 1 /* NETWORK_ERROR */,
                                         0, errorMsg, null);
                        }
                    });
                }
            }
        }).start();
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

    /**
     * Start monitoring network connectivity. Called from native code via JNI.
     * Uses ConnectivityManager.registerDefaultNetworkCallback (API 26+).
     * Updates are delivered via onNetworkStatusChange JNI callback.
     */
    public void startNetworkMonitoring() {
        try {
            connectivityManager = (ConnectivityManager) getSystemService(Context.CONNECTIVITY_SERVICE);
            if (connectivityManager == null) {
                android.util.Log.e("NetworkStatusBridge", "ConnectivityManager unavailable");
                return;
            }

            networkCallback = new ConnectivityManager.NetworkCallback() {
                @Override
                public void onCapabilitiesChanged(Network network, NetworkCapabilities capabilities) {
                    int transport;
                    if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                        transport = 1; /* NETWORK_TRANSPORT_WIFI */
                    } else if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) {
                        transport = 2; /* NETWORK_TRANSPORT_CELLULAR */
                    } else if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) {
                        transport = 3; /* NETWORK_TRANSPORT_ETHERNET */
                    } else {
                        transport = 4; /* NETWORK_TRANSPORT_OTHER */
                    }
                    final int t = transport;
                    runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            onNetworkStatusChange(1, t);
                        }
                    });
                }

                @Override
                public void onLost(Network network) {
                    runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            onNetworkStatusChange(0, 0); /* disconnected, NETWORK_TRANSPORT_NONE */
                        }
                    });
                }
            };

            connectivityManager.registerDefaultNetworkCallback(networkCallback);
        } catch (Exception e) {
            android.util.Log.e("NetworkStatusBridge",
                "startNetworkMonitoring failed: " + e.getMessage());
        }
    }

    /**
     * Stop monitoring network connectivity. Called from native code via JNI.
     */
    public void stopNetworkMonitoring() {
        try {
            if (connectivityManager != null && networkCallback != null) {
                connectivityManager.unregisterNetworkCallback(networkCallback);
                networkCallback = null;
            }
        } catch (Exception e) {
            android.util.Log.e("NetworkStatusBridge",
                "stopNetworkMonitoring failed: " + e.getMessage());
        }
    }

    /**
     * Start an auth session by opening the system browser. Called from native code via JNI.
     * requestId: opaque ID passed back in the result callback.
     * authUrl: URL to open in the system browser.
     * callbackScheme: URL scheme for the redirect (e.g. "haskellmobile").
     */
    public void startAuthSession(int requestId, String authUrl, String callbackScheme) {
        pendingAuthRequestId = requestId;
        authRedirectReceived = false;
        Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(authUrl));
        startActivity(intent);
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        if (intent.getData() != null && pendingAuthRequestId >= 0) {
            authRedirectReceived = true;
            onAuthSessionResult(pendingAuthRequestId, 0,
                                 intent.getData().toString(), null);
            pendingAuthRequestId = -1;
        }
    }

    /**
     * Start a camera session using Camera2 API. Called from native code via JNI.
     * facing: 0 = back camera, 1 = front camera.
     */
    public void startCameraSession(int facing) {
        try {
            CameraManager cameraManager = (CameraManager) getSystemService(Context.CAMERA_SERVICE);
            if (cameraManager == null) {
                android.util.Log.e("CameraBridge", "CameraManager unavailable");
                return;
            }

            int lensFacing = (facing == 1)
                ? CameraCharacteristics.LENS_FACING_FRONT
                : CameraCharacteristics.LENS_FACING_BACK;

            String targetCameraId = null;
            for (String cameraId : cameraManager.getCameraIdList()) {
                CameraCharacteristics characteristics = cameraManager.getCameraCharacteristics(cameraId);
                Integer cameraLensFacing = characteristics.get(CameraCharacteristics.LENS_FACING);
                if (cameraLensFacing != null && cameraLensFacing == lensFacing) {
                    targetCameraId = cameraId;
                    break;
                }
            }

            if (targetCameraId == null) {
                android.util.Log.e("CameraBridge", "No camera found for facing=" + facing);
                return;
            }

            /* Set up an ImageReader for photo capture */
            imageReader = ImageReader.newInstance(1920, 1080, ImageFormat.JPEG, 2);

            cameraManager.openCamera(targetCameraId, new CameraDevice.StateCallback() {
                @Override
                public void onOpened(CameraDevice camera) {
                    cameraDevice = camera;
                    android.util.Log.i("CameraBridge", "Camera opened: " + camera.getId());
                }

                @Override
                public void onDisconnected(CameraDevice camera) {
                    camera.close();
                    cameraDevice = null;
                    android.util.Log.w("CameraBridge", "Camera disconnected");
                }

                @Override
                public void onError(CameraDevice camera, int error) {
                    camera.close();
                    cameraDevice = null;
                    android.util.Log.e("CameraBridge", "Camera error: " + error);
                }
            }, null);
        } catch (CameraAccessException e) {
            android.util.Log.e("CameraBridge",
                "startCameraSession: camera access error: " + e.getMessage());
        } catch (SecurityException e) {
            android.util.Log.e("CameraBridge",
                "startCameraSession: permission denied: " + e.getMessage());
        } catch (Exception e) {
            android.util.Log.e("CameraBridge",
                "startCameraSession failed: " + e.getMessage());
        }
    }

    /**
     * Stop the active camera session. Called from native code via JNI.
     */
    public void stopCameraSession() {
        try {
            if (cameraCaptureSession != null) {
                cameraCaptureSession.close();
                cameraCaptureSession = null;
            }
            if (cameraDevice != null) {
                cameraDevice.close();
                cameraDevice = null;
            }
            if (imageReader != null) {
                imageReader.close();
                imageReader = null;
            }
        } catch (Exception e) {
            android.util.Log.e("CameraBridge",
                "stopCameraSession failed: " + e.getMessage());
        }
    }

    /**
     * Capture a photo. Called from native code via JNI.
     * requestId: opaque ID passed back in the result callback.
     */
    public void capturePhoto(final int requestId) {
        try {
            if (cameraDevice == null) {
                android.util.Log.e("CameraBridge", "capturePhoto: no camera device");
                onCameraResult(requestId, 4 /* CAMERA_ERROR */, null, 0, 0);
                return;
            }

            final ImageReader reader = ImageReader.newInstance(1920, 1080, ImageFormat.JPEG, 1);
            reader.setOnImageAvailableListener(new ImageReader.OnImageAvailableListener() {
                @Override
                public void onImageAvailable(ImageReader r) {
                    Image image = r.acquireLatestImage();
                    if (image != null) {
                        int imgWidth = image.getWidth();
                        int imgHeight = image.getHeight();
                        java.nio.ByteBuffer buffer = image.getPlanes()[0].getBuffer();
                        byte[] bytes = new byte[buffer.remaining()];
                        buffer.get(bytes);
                        image.close();

                        onCameraResult(requestId, 0 /* CAMERA_SUCCESS */,
                            bytes, imgWidth, imgHeight);
                    }
                    reader.close();
                }
            }, null);

            final CaptureRequest.Builder captureBuilder =
                cameraDevice.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE);
            captureBuilder.addTarget(reader.getSurface());

            cameraDevice.createCaptureSession(
                java.util.Arrays.asList(reader.getSurface()),
                new CameraCaptureSession.StateCallback() {
                    @Override
                    public void onConfigured(CameraCaptureSession session) {
                        try {
                            session.capture(captureBuilder.build(),
                                new CameraCaptureSession.CaptureCallback() {}, null);
                        } catch (CameraAccessException e) {
                            android.util.Log.e("CameraBridge",
                                "capturePhoto: capture failed: " + e.getMessage());
                            onCameraResult(requestId, 4 /* CAMERA_ERROR */,
                                null, 0, 0);
                        }
                    }

                    @Override
                    public void onConfigureFailed(CameraCaptureSession session) {
                        android.util.Log.e("CameraBridge",
                            "capturePhoto: session config failed");
                        onCameraResult(requestId, 4 /* CAMERA_ERROR */,
                            null, 0, 0);
                    }
                }, null);
        } catch (CameraAccessException e) {
            android.util.Log.e("CameraBridge",
                "capturePhoto: camera access error: " + e.getMessage());
            onCameraResult(requestId, 4 /* CAMERA_ERROR */, null, 0, 0);
        } catch (Exception e) {
            android.util.Log.e("CameraBridge",
                "capturePhoto failed: " + e.getMessage());
            onCameraResult(requestId, 4 /* CAMERA_ERROR */, null, 0, 0);
        }
    }

    /**
     * Start recording video with per-frame and per-audio-chunk push
     * callbacks. Called from native code via JNI.
     * requestId: opaque ID passed back in callbacks.
     *
     * Uses ImageReader for JPEG video frames and AudioRecord for PCM
     * audio chunks, pushing each to Haskell via onVideoFrame/onAudioChunk.
     */
    public void startVideoCapture(final int requestId) {
        try {
            if (cameraDevice == null) {
                android.util.Log.e("CameraBridge", "startVideoCapture: no camera device");
                onCameraResult(requestId, 4 /* CAMERA_ERROR */, null, 0, 0);
                return;
            }

            videoRequestId = requestId;

            /* ImageReader for JPEG video frames */
            videoFrameReader = ImageReader.newInstance(1920, 1080, ImageFormat.JPEG, 2);
            videoFrameReader.setOnImageAvailableListener(new ImageReader.OnImageAvailableListener() {
                @Override
                public void onImageAvailable(ImageReader r) {
                    Image image = r.acquireLatestImage();
                    if (image != null) {
                        int imgWidth = image.getWidth();
                        int imgHeight = image.getHeight();
                        java.nio.ByteBuffer buffer = image.getPlanes()[0].getBuffer();
                        byte[] bytes = new byte[buffer.remaining()];
                        buffer.get(bytes);
                        image.close();
                        onVideoFrame(requestId, bytes, imgWidth, imgHeight);
                    }
                }
            }, null);

            final CaptureRequest.Builder recordBuilder =
                cameraDevice.createCaptureRequest(CameraDevice.TEMPLATE_RECORD);
            recordBuilder.addTarget(videoFrameReader.getSurface());

            cameraDevice.createCaptureSession(
                java.util.Arrays.asList(videoFrameReader.getSurface()),
                new CameraCaptureSession.StateCallback() {
                    @Override
                    public void onConfigured(CameraCaptureSession session) {
                        cameraCaptureSession = session;
                        try {
                            session.setRepeatingRequest(recordBuilder.build(), null, null);
                            android.util.Log.i("CameraBridge", "Video frame capture started");
                        } catch (CameraAccessException e) {
                            android.util.Log.e("CameraBridge",
                                "startVideoCapture: repeating request failed: " + e.getMessage());
                            onCameraResult(requestId, 4 /* CAMERA_ERROR */,
                                null, 0, 0);
                        }
                    }

                    @Override
                    public void onConfigureFailed(CameraCaptureSession session) {
                        android.util.Log.e("CameraBridge",
                            "startVideoCapture: session config failed");
                        onCameraResult(requestId, 4 /* CAMERA_ERROR */,
                            null, 0, 0);
                    }
                }, null);

            /* AudioRecord for PCM audio chunks */
            try {
                int sampleRate = 44100;
                int channelConfig = android.media.AudioFormat.CHANNEL_IN_MONO;
                int audioFormat = android.media.AudioFormat.ENCODING_PCM_16BIT;
                int bufferSize = android.media.AudioRecord.getMinBufferSize(
                    sampleRate, channelConfig, audioFormat);
                audioRecord = new android.media.AudioRecord(
                    android.media.MediaRecorder.AudioSource.MIC,
                    sampleRate, channelConfig, audioFormat, bufferSize);
                audioRecording = true;
                audioRecord.startRecording();
                audioRecordThread = new Thread(new Runnable() {
                    @Override
                    public void run() {
                        byte[] buffer = new byte[4096];
                        while (audioRecording) {
                            int read = audioRecord.read(buffer, 0, buffer.length);
                            if (read > 0) {
                                byte[] chunk = new byte[read];
                                System.arraycopy(buffer, 0, chunk, 0, read);
                                onAudioChunk(requestId, chunk);
                            }
                        }
                    }
                });
                audioRecordThread.start();
            } catch (Exception e) {
                android.util.Log.w("CameraBridge",
                    "AudioRecord setup failed (audio callbacks disabled): " + e.getMessage());
            }
        } catch (Exception e) {
            android.util.Log.e("CameraBridge",
                "startVideoCapture failed: " + e.getMessage());
            onCameraResult(requestId, 4 /* CAMERA_ERROR */, null, 0, 0);
        }
    }

    /**
     * Stop recording video. Called from native code via JNI.
     * Stops frame/audio capture and fires the completion callback.
     */
    public void stopVideoCapture() {
        try {
            /* Stop audio recording */
            audioRecording = false;
            if (audioRecordThread != null) {
                try { audioRecordThread.join(1000); } catch (InterruptedException ignored) {}
                audioRecordThread = null;
            }
            if (audioRecord != null) {
                audioRecord.stop();
                audioRecord.release();
                audioRecord = null;
            }

            /* Stop video frame capture */
            if (cameraCaptureSession != null) {
                cameraCaptureSession.close();
                cameraCaptureSession = null;
            }
            if (videoFrameReader != null) {
                videoFrameReader.close();
                videoFrameReader = null;
            }

            onCameraResult(videoRequestId, 0 /* CAMERA_SUCCESS */,
                null, 0, 0);
        } catch (Exception e) {
            android.util.Log.e("CameraBridge",
                "stopVideoCapture failed: " + e.getMessage());
            onCameraResult(videoRequestId, 4 /* CAMERA_ERROR */,
                null, 0, 0);
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

        // Auth session cancellation detection: if we return to the activity
        // without receiving a redirect, the user cancelled the browser.
        if (pendingAuthRequestId >= 0 && !authRedirectReceived) {
            final int requestId = pendingAuthRequestId;
            new Handler().postDelayed(new Runnable() {
                @Override
                public void run() {
                    if (pendingAuthRequestId == requestId && !authRedirectReceived) {
                        onAuthSessionResult(requestId, 1 /* CANCELLED */, null, null);
                        pendingAuthRequestId = -1;
                    }
                }
            }, 500);
        }
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
