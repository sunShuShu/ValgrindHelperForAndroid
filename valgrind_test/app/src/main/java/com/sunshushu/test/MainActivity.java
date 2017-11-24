package com.sunshushu.test;

import android.support.v7.app.AppCompatActivity;
import android.os.Bundle;
import android.view.View;
import android.widget.Button;

public class MainActivity extends AppCompatActivity implements View.OnClickListener {

    // Used to load the 'native-lib' library on application startup.
    static {
        System.loadLibrary("native-lib");
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        Button btn1 = (Button)findViewById(R.id.btn_issue);
        Button btn2 = (Button)findViewById(R.id.btn_exit);
        btn1.setOnClickListener(this);
        btn2.setOnClickListener(this);
    }

    public void onClick(View viewv)
    {
        int id = viewv.getId();
        if (id == R.id.btn_issue)
        {
            fromIssue();
        }
        else if (id == R.id.btn_exit)
        {
            System.exit(0);
        }
    }

    private native void fromIssue();
}
