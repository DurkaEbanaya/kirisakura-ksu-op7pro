package de.robv.android.xposed;

import java.lang.reflect.Method;
import java.util.Set;

public class XposedBridge {
    public static Set<XC_MethodHook.Unhook> hookAllMethods(Class<?> clazz, String methodName, XC_MethodHook callback) {
        return null;
    }

    public static Object invokeOriginalMethod(Method method, Object thisObject, Object[] args) throws Throwable {
        return null;
    }

    public static void log(String text) {}

    public static void log(Throwable t) {}
}
