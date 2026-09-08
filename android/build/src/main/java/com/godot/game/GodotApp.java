/**************************************************************************/
/*  GodotApp.java                                                         */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

package com.godot.game;

import org.godotengine.godot.Godot;
import org.godotengine.godot.GodotActivity;

import android.content.Intent;
import android.os.Bundle;
import android.util.Log;

import androidx.activity.EdgeToEdge;
import androidx.core.splashscreen.SplashScreen;

import java.io.File;
import java.io.FileOutputStream;

/**
 * Template activity for Godot Android builds.
 * Feel free to extend and modify this class for your custom logic.
 */
public class GodotApp extends GodotActivity {
	static {
		// .NET libraries.
		if (BuildConfig.FLAVOR.equals("mono")) {
			try {
				Log.v("GODOT", "Loading System.Security.Cryptography.Native.Android library");
				System.loadLibrary("System.Security.Cryptography.Native.Android");
			} catch (UnsatisfiedLinkError e) {
				Log.e("GODOT", "Unable to load System.Security.Cryptography.Native.Android library");
			}
		}
	}

	/**
	 * Deep-link hand-off file. Godot 4.6 maps user:// to the app files dir
	 * (GodotIO.getDataDir()), so GDScript reads this exact path as
	 * user://deep_link_uri.txt.
	 */
	private static final String DEEP_LINK_FILE = "deep_link_uri.txt";

	/**
	 * Forwards a VIEW intent's data URI (picturepuzzle://callback?...) into the
	 * game by writing it to a file in the app files dir. The identity source
	 * polls user://deep_link_uri.txt while a sign-in is pending, then deletes
	 * the file. File (not callback/JNI) because stock Godot 4.6 exposes no
	 * runtime intent API.
	 */
	private void forwardDeepLink(Intent intent) {
		if (intent == null || intent.getData() == null) {
			return;
		}
		String uri = intent.getDataString();
		try {
			File f = new File(getFilesDir(), DEEP_LINK_FILE);
			try (FileOutputStream out = new FileOutputStream(f)) {
				out.write(uri.getBytes("UTF-8"));
			}
			Log.v("GODOT", "Stored deep link uri: " + uri);
		} catch (Exception e) {
			Log.e("GODOT", "Unable to store deep link uri", e);
		}
	}

	private final Runnable updateWindowAppearance = () -> {
		Godot godot = getGodot();
		if (godot != null) {
			godot.enableImmersiveMode(godot.isInImmersiveMode(), true);
			godot.enableEdgeToEdge(godot.isInEdgeToEdgeMode(), true);
			godot.setSystemBarsAppearance();
		}
	};

	@Override
	public void onCreate(Bundle savedInstanceState) {
		SplashScreen.installSplashScreen(this);
		EdgeToEdge.enable(this);
		super.onCreate(savedInstanceState);
		// Cold start: the URI arrives in the launch intent and is available here
		// before the game main loop exists — the file write is in place by the
		// time the identity source's _ready() runs.
		forwardDeepLink(getIntent());
	}

	@Override
	protected void onNewIntent(Intent newIntent) {
		super.onNewIntent(newIntent);
		// Warm start: the game is already running in the background while the
		// browser finishes OAuth — deliver the returned URI to it.
		forwardDeepLink(newIntent);
	}

	@Override
	public void onResume() {
		super.onResume();
		updateWindowAppearance.run();
	}

	@Override
	public void onGodotMainLoopStarted() {
		super.onGodotMainLoopStarted();
		runOnUiThread(updateWindowAppearance);
	}

	@Override
	public void onGodotForceQuit(Godot instance) {
		if (!BuildConfig.FLAVOR.equals("instrumented")) {
			// For instrumented builds, we disable force-quitting to allow the instrumented tests to complete
			// successfully, otherwise they fail when the process crashes.
			super.onGodotForceQuit(instance);
		}
	}
}
