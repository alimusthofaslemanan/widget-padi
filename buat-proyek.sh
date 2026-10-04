#!/bin/bash
# Membuat seluruh proyek Android "Widget Padi" (mandiri, tanpa PWA)
set -e
P=app/src/main
J=$P/java/com/padi/widget
R=$P/res
mkdir -p $J $R/xml $R/drawable $R/layout

cat > settings.gradle <<'EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "WidgetPadi"
include ':app'
EOF

cat > build.gradle <<'EOF'
plugins {
    id 'com.android.application' version '8.5.2' apply false
}
EOF

cat > gradle.properties <<'EOF'
org.gradle.jvmargs=-Xmx2g -Dfile.encoding=UTF-8
android.nonTransitiveRClass=true
EOF

cat > app/build.gradle <<'EOF'
plugins {
    id 'com.android.application'
}
android {
    namespace 'com.padi.widget'
    compileSdk 34
    defaultConfig {
        applicationId "com.padi.widget"
        minSdk 26
        targetSdk 34
        versionCode 1
        versionName "1.0"
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}
tasks.withType(JavaCompile) {
    options.encoding = 'UTF-8'
}
EOF

cat > $P/AndroidManifest.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    <application
        android:label="Widget Padi"
        android:theme="@android:style/Theme.Material.Light.NoActionBar">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <receiver android:name=".PadiWidget" android:exported="true">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE"/>
            </intent-filter>
            <meta-data android:name="android.appwidget.provider" android:resource="@xml/padi_widget_info"/>
        </receiver>
    </application>
</manifest>
EOF

cat > $R/drawable/widget_bg.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android">
    <solid android:color="#3F7A47"/>
    <corners android:radius="20dp"/>
</shape>
EOF

cat > $R/xml/padi_widget_info.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="250dp"
    android:minHeight="130dp"
    android:targetCellWidth="4"
    android:targetCellHeight="2"
    android:updatePeriodMillis="1800000"
    android:resizeMode="horizontal|vertical"
    android:widgetCategory="home_screen"
    android:initialLayout="@layout/widget_padi"/>
EOF

cat > $R/layout/widget_padi.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:padding="12dp"
    android:background="@drawable/widget_bg">
    <TextView android:id="@+id/hst" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="HST -" android:textColor="#FFFFFF" android:textSize="22sp" android:textStyle="bold"
        android:maxLines="1" android:ellipsize="end"/>
    <TextView android:id="@+id/panen" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:layout_marginTop="2dp" android:textColor="#FFFFFF" android:textSize="12sp"
        android:maxLines="1" android:ellipsize="end"/>
    <TextView android:id="@+id/cuaca" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:layout_marginTop="2dp" android:textColor="#FFFFFF" android:textSize="12sp"
        android:maxLines="1" android:ellipsize="end"/>
    <TextView android:id="@+id/sekarang" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:layout_marginTop="6dp" android:textColor="#FFFFFF" android:textSize="12sp" android:textStyle="bold"
        android:maxLines="2" android:ellipsize="end"/>
    <TextView android:id="@+id/berikut" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:layout_marginTop="2dp" android:textColor="#DDEEDD" android:textSize="12sp"
        android:maxLines="1" android:ellipsize="end"/>
</LinearLayout>
EOF

cat > $J/Core.java <<'EOF'
package com.padi.widget;

import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.text.SimpleDateFormat;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.Date;
import java.util.Locale;

public class Core {
    static class Phase {
        String name; int from, to;
        Phase(String n, int f, int t) { name = n; from = f; to = t; }
    }

    // Jadwal perawatan (HST = hari setelah tanam)
    static final Phase[] PHASES = {
        new Phase("Persemaian Benih", -21, -1),
        new Phase("Olah Lahan & Tanam", -10, 0),
        new Phase("Pemupukan Dasar", 7, 14),
        new Phase("Penyiangan I", 15, 21),
        new Phase("Pemupukan Susulan II", 25, 30),
        new Phase("Penyiangan II", 30, 40),
        new Phase("Primordia / Pemupukan III", 40, 50),
        new Phase("Pembungaan", 55, 70),
        new Phase("Pengisian Bulir", 70, 90),
        new Phase("Masak Susu-Kuning", 90, 105),
        new Phase("Panen", 105, 120)
    };

    static SharedPreferences sp(Context c) {
        return c.getSharedPreferences("padi", Context.MODE_PRIVATE);
    }

    static LocalDate tanam(Context c) {
        String s = sp(c).getString("tanam", null);
        if (s == null) return null;
        try { return LocalDate.parse(s); } catch (Exception e) { return null; }
    }

    static long hst(Context c) {
        LocalDate t = tanam(c);
        return ChronoUnit.DAYS.between(t, LocalDate.now());
    }

    static String hstText(Context c) {
        if (tanam(c) == null) return "Atur tanggal tanam";
        long h = hst(c);
        return h < 0 ? "H" + h + " sebelum tanam" : "HST " + h;
    }

    static String panenText(Context c) {
        LocalDate t = tanam(c);
        if (t == null) return "Estimasi panen: -";
        int umur = sp(c).getInt("umur", 110);
        LocalDate p = t.plusDays(umur);
        long sisa = ChronoUnit.DAYS.between(LocalDate.now(), p);
        String tgl = p.format(DateTimeFormatter.ofPattern("d MMM yyyy", new Locale("id")));
        if (sisa > 0) return "Est. panen " + tgl + " (" + sisa + " hari lagi)";
        if (sisa == 0) return "Est. panen hari ini (" + tgl + ")";
        return "Est. panen " + tgl + " (sudah lewat)";
    }

    static String sekarangText(Context c) {
        if (tanam(c) == null) return "Jadwal: ketuk untuk mengatur";
        long h = hst(c);
        StringBuilder sb = new StringBuilder();
        for (Phase p : PHASES) {
            if (h >= p.from && h <= p.to) {
                if (sb.length() > 0) sb.append(" + ");
                sb.append(p.name);
            }
        }
        if (sb.length() == 0) return "Sekarang: perawatan rutin (jaga air & hama)";
        return "Sekarang: " + sb;
    }

    static String berikutText(Context c) {
        if (tanam(c) == null) return "";
        long h = hst(c);
        Phase next = null;
        for (Phase p : PHASES) {
            if (p.from > h && (next == null || p.from < next.from)) next = p;
        }
        if (next == null) return "Berikut: musim tanam selesai";
        long d = next.from - h;
        return "Berikut: " + next.name + " (" + d + " hari lagi)";
    }

    static String cuacaText(Context c) {
        SharedPreferences p = sp(c);
        String s = p.getString("cuaca", null);
        if (s == null) {
            if (p.getString("lat", "").isEmpty()) return "Cuaca: atur lokasi di app";
            return "Cuaca: menunggu internet";
        }
        String jam = new SimpleDateFormat("HH:mm", new Locale("id"))
                .format(new Date(p.getLong("cuaca_t", 0)));
        return s + " (" + jam + ")";
    }

    static String codeText(int c) {
        if (c == 0) return "Cerah";
        if (c <= 2) return "Cerah berawan";
        if (c == 3) return "Berawan";
        if (c == 45 || c == 48) return "Berkabut";
        if (c >= 51 && c <= 57) return "Gerimis";
        if (c == 61) return "Hujan ringan";
        if (c == 63) return "Hujan sedang";
        if (c == 65 || c == 66 || c == 67) return "Hujan lebat";
        if (c >= 71 && c <= 77) return "Salju";
        if (c >= 80 && c <= 82) return "Hujan deras sesaat";
        if (c >= 95) return "Badai petir";
        return "Berawan";
    }

    // Ambil cuaca dari Open-Meteo (gratis, tanpa kunci API)
    static boolean fetchWeather(Context c) {
        SharedPreferences p = sp(c);
        String lat = p.getString("lat", "");
        String lon = p.getString("lon", "");
        if (lat.isEmpty() || lon.isEmpty()) return false;
        HttpURLConnection h = null;
        try {
            String u = "https://api.open-meteo.com/v1/forecast?latitude=" + URLEncoder.encode(lat, "UTF-8")
                    + "&longitude=" + URLEncoder.encode(lon, "UTF-8")
                    + "&current=temperature_2m,weather_code"
                    + "&daily=precipitation_probability_max&forecast_days=1&timezone=auto";
            h = (HttpURLConnection) new URL(u).openConnection();
            h.setConnectTimeout(8000);
            h.setReadTimeout(8000);
            BufferedReader r = new BufferedReader(new InputStreamReader(h.getInputStream()));
            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = r.readLine()) != null) sb.append(line);
            r.close();
            JSONObject root = new JSONObject(sb.toString());
            JSONObject cur = root.getJSONObject("current");
            double t = cur.getDouble("temperature_2m");
            int code = cur.getInt("weather_code");
            String out = codeText(code) + ", " + Math.round(t) + "°C";
            JSONObject daily = root.optJSONObject("daily");
            if (daily != null) {
                JSONArray a = daily.optJSONArray("precipitation_probability_max");
                if (a != null && a.length() > 0 && !a.isNull(0)) {
                    out += " · hujan " + a.getInt(0) + "%";
                }
            }
            p.edit().putString("cuaca", out).putLong("cuaca_t", System.currentTimeMillis()).apply();
            return true;
        } catch (Exception e) {
            return false;
        } finally {
            if (h != null) h.disconnect();
        }
    }

    static void refreshWidgets(Context c) {
        AppWidgetManager m = AppWidgetManager.getInstance(c);
        int[] ids = m.getAppWidgetIds(new ComponentName(c, PadiWidget.class));
        if (ids.length == 0) return;
        Intent i = new Intent(c, PadiWidget.class);
        i.setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE);
        i.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids);
        c.sendBroadcast(i);
    }
}
EOF

cat > $J/PadiWidget.java <<'EOF'
package com.padi.widget;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;
import android.content.Intent;
import android.widget.RemoteViews;

public class PadiWidget extends AppWidgetProvider {

    @Override
    public void onUpdate(final Context ctx, final AppWidgetManager mgr, final int[] ids) {
        render(ctx, mgr, ids);
        final PendingResult pr = goAsync();
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    if (Core.fetchWeather(ctx)) render(ctx, mgr, ids);
                } catch (Exception e) {
                    // abaikan, pakai data cuaca terakhir
                } finally {
                    pr.finish();
                }
            }
        }).start();
    }

    static void render(Context ctx, AppWidgetManager mgr, int[] ids) {
        for (int id : ids) {
            RemoteViews v = new RemoteViews(ctx.getPackageName(), R.layout.widget_padi);
            v.setTextViewText(R.id.hst, Core.hstText(ctx));
            v.setTextViewText(R.id.panen, Core.panenText(ctx));
            v.setTextViewText(R.id.cuaca, Core.cuacaText(ctx));
            v.setTextViewText(R.id.sekarang, Core.sekarangText(ctx));
            v.setTextViewText(R.id.berikut, Core.berikutText(ctx));
            Intent i = new Intent(ctx, MainActivity.class);
            PendingIntent pi = PendingIntent.getActivity(ctx, 0, i,
                    PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
            v.setOnClickPendingIntent(R.id.root, pi);
            mgr.updateAppWidget(id, v);
        }
    }
}
EOF

cat > $J/MainActivity.java <<'EOF'
package com.padi.widget;

import android.Manifest;
import android.app.Activity;
import android.app.DatePickerDialog;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationManager;
import android.os.Bundle;
import android.text.InputType;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;
import java.time.LocalDate;

public class MainActivity extends Activity {
    private String tanam = null;
    private Button btnTanggal;
    private EditText etUmur, etLat, etLon;

    private int dp(int v) {
        return (int) (v * getResources().getDisplayMetrics().density);
    }

    private TextView label(String t) {
        TextView tv = new TextView(this);
        tv.setText(t);
        tv.setTextSize(15);
        tv.setPadding(0, dp(16), 0, dp(4));
        return tv;
    }

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        SharedPreferences p = Core.sp(this);
        tanam = p.getString("tanam", null);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(20), dp(32), dp(20), dp(24));

        TextView title = new TextView(this);
        title.setText("Widget Padi");
        title.setTextSize(24);
        root.addView(title);

        root.addView(label("Tanggal tanam padi"));
        btnTanggal = new Button(this);
        btnTanggal.setText(tanam == null ? "Pilih tanggal" : tanam);
        btnTanggal.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { pilihTanggal(); }
        });
        root.addView(btnTanggal);

        root.addView(label("Umur panen (hari setelah tanam)"));
        etUmur = new EditText(this);
        etUmur.setInputType(InputType.TYPE_CLASS_NUMBER);
        etUmur.setText(String.valueOf(p.getInt("umur", 110)));
        root.addView(etUmur);

        root.addView(label("Lokasi sawah (untuk cuaca)"));
        etLat = new EditText(this);
        etLat.setHint("Lintang, contoh -6.9175");
        etLat.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL | InputType.TYPE_NUMBER_FLAG_SIGNED);
        etLat.setText(p.getString("lat", ""));
        root.addView(etLat);
        etLon = new EditText(this);
        etLon.setHint("Bujur, contoh 107.6191");
        etLon.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL | InputType.TYPE_NUMBER_FLAG_SIGNED);
        etLon.setText(p.getString("lon", ""));
        root.addView(etLon);

        Button btnLok = new Button(this);
        btnLok.setText("Pakai lokasi saya sekarang");
        btnLok.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { ambilLokasi(); }
        });
        root.addView(btnLok);

        Button btnSimpan = new Button(this);
        btnSimpan.setText("SIMPAN");
        btnSimpan.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { simpan(); }
        });
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.topMargin = dp(24);
        root.addView(btnSimpan, lp);

        TextView info = new TextView(this);
        info.setText("Setelah disimpan, tekan lama layar utama > Widget > Widget Padi.");
        info.setPadding(0, dp(16), 0, 0);
        root.addView(info);

        ScrollView sv = new ScrollView(this);
        sv.addView(root);
        setContentView(sv);
    }

    private void pilihTanggal() {
        LocalDate d = LocalDate.now();
        if (tanam != null) {
            try { d = LocalDate.parse(tanam); } catch (Exception e) { }
        }
        new DatePickerDialog(this, new DatePickerDialog.OnDateSetListener() {
            public void onDateSet(android.widget.DatePicker view, int y, int m, int day) {
                tanam = LocalDate.of(y, m + 1, day).toString();
                btnTanggal.setText(tanam);
            }
        }, d.getYear(), d.getMonthValue() - 1, d.getDayOfMonth()).show();
    }

    private void ambilLokasi() {
        if (checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.ACCESS_COARSE_LOCATION}, 1);
            return;
        }
        LocationManager lm = (LocationManager) getSystemService(Context.LOCATION_SERVICE);
        Location best = null;
        for (String prov : lm.getProviders(true)) {
            try {
                Location l = lm.getLastKnownLocation(prov);
                if (l != null && (best == null || l.getTime() > best.getTime())) best = l;
            } catch (SecurityException e) { }
        }
        if (best == null) {
            Toast.makeText(this, "Lokasi belum tersedia. Nyalakan GPS, buka Google Maps sebentar, lalu coba lagi atau isi manual.", Toast.LENGTH_LONG).show();
            return;
        }
        etLat.setText(String.format(java.util.Locale.US, "%.4f", best.getLatitude()));
        etLon.setText(String.format(java.util.Locale.US, "%.4f", best.getLongitude()));
        Toast.makeText(this, "Lokasi terisi", Toast.LENGTH_SHORT).show();
    }

    @Override
    public void onRequestPermissionsResult(int code, String[] perms, int[] res) {
        super.onRequestPermissionsResult(code, perms, res);
        if (code == 1 && res.length > 0 && res[0] == PackageManager.PERMISSION_GRANTED) ambilLokasi();
    }

    private void simpan() {
        int umur = 110;
        try { umur = Integer.parseInt(etUmur.getText().toString().trim()); } catch (Exception e) { }
        SharedPreferences.Editor e = Core.sp(this).edit();
        if (tanam != null) e.putString("tanam", tanam);
        e.putInt("umur", umur);
        e.putString("lat", etLat.getText().toString().trim().replace(',', '.'));
        e.putString("lon", etLon.getText().toString().trim().replace(',', '.'));
        e.apply();
        Core.refreshWidgets(this);
        Toast.makeText(this, "Tersimpan. Widget diperbarui.", Toast.LENGTH_SHORT).show();
    }
}
EOF
echo "Proyek Widget Padi berhasil dibuat"
