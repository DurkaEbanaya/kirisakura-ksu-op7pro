package com.durka.oemfix;

import android.util.Log;

import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodReplacement;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.XposedHelpers;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

public class FixEntry implements IXposedHookLoadPackage {

    private static final String TAG = "OemFix";
    private static final String SETTINGS_PKG = "com.android.settings";
    private static final String CONTROLLER_CLASS =
        "com.android.settings.development.OemUnlockPreferenceController";

    @Override
    public void handleLoadPackage(XC_LoadPackage.LoadPackageParam lpparam) throws Throwable {
        if (!SETTINGS_PKG.equals(lpparam.packageName)) return;

        Class<?> clazz = XposedHelpers.findClass(CONTROLLER_CLASS, lpparam.classLoader);
        if (clazz == null) {
            Log.e(TAG, "Could not find " + CONTROLLER_CLASS);
            return;
        }

        // Hook updateState(): skip entirely if mOemLockManager is null.
        //
        // Root cause: on OOS 11 (GM1910_21_220617), OemLockManager is not
        // registered in SystemServiceRegistry, so getSystemService() returns
        // null. The OemUnlockPreferenceController constructor posts a callback
        // that calls updateState() → isOemUnlockedAllowed() →
        // mOemLockManager.isOemUnlockAllowed() → NPE → crash.
        //
        // isAvailable() correctly returns false when mOemLockManager is null,
        // but the callback runs before isAvailable() is checked — an AOSP 11
        // bug fixed in later versions.
        //
        // This hook makes the class of errors architecturally impossible:
        // any code path through updateState with a null manager is short-
        // circuited to a no-op, regardless of how many future callbacks or
        // code changes might call it.
        XposedBridge.hookAllMethods(clazz, "updateState", new XC_MethodReplacement() {
            @Override
            protected Object replaceHookedMethod(MethodHookParam param) throws Throwable {
                Object mgr = XposedHelpers.getObjectField(param.thisObject, "mOemLockManager");
                if (mgr == null) {
                    Log.d(TAG, "Skipping updateState: mOemLockManager is null");
                    return null; // void method
                }
                return XposedBridge.invokeOriginalMethod(
                    param.method, param.thisObject, param.args);
            }
        });

        // Also hook isOemUnlockedAllowed() as a belt-and-suspenders measure:
        // if any other code path calls it directly, return false instead of
        // crashing.
        XposedBridge.hookAllMethods(clazz, "isOemUnlockedAllowed", new XC_MethodReplacement() {
            @Override
            protected Object replaceHookedMethod(MethodHookParam param) throws Throwable {
                Object mgr = XposedHelpers.getObjectField(param.thisObject, "mOemLockManager");
                if (mgr == null) {
                    Log.d(TAG, "Skipping isOemUnlockedAllowed: mOemLockManager is null");
                    return false;
                }
                return XposedBridge.invokeOriginalMethod(
                    param.method, param.thisObject, param.args);
            }
        });

        Log.i(TAG, "Hooks installed for " + SETTINGS_PKG);
    }
}
