package me.jappie.haskellmobile;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;

public class MainActivity extends Activity {

    static {
        System.loadLibrary("haskellmobile");
    }

    private native String greet(String name);
    private native void onLifecycleCreate();
    private native void onLifecycleStart();
    private native void onLifecycleResume();
    private native void onLifecyclePause();
    private native void onLifecycleStop();
    private native void onLifecycleDestroy();
    private native void onLifecycleLowMemory();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        onLifecycleCreate();
        setContentView(R.layout.activity_main);

        TextView greetingText = findViewById(R.id.greeting_text);
        String greeting = greet("Android");
        greetingText.setText(greeting);
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
