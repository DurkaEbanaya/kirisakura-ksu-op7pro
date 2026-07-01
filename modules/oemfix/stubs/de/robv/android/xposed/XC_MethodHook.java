package de.robv.android.xposed;

public abstract class XC_MethodHook {
    public class MethodHookParam {
        public java.lang.reflect.Method method;
        public Object thisObject;
        public Object[] args;
        private Object result;
        public void setResult(Object result) { this.result = result; }
        public Object getResult() { return result; }
    }
    public interface Unhook {}
    protected void beforeHookedMethod(MethodHookParam param) throws Throwable {}
    protected void afterHookedMethod(MethodHookParam param) throws Throwable {}
}
