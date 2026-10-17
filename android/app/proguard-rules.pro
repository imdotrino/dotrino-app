# El puente que la página web llama por NOMBRE (window.DotrinoNative.version(), …): si R8 lo
# renombra, la página deja de ver la app nativa. La regla por defecto de Android ya guarda los
# métodos con @JavascriptInterface; esta guarda además la clase, que es lo que se registra.
-keep class com.dotrino.app.MainActivity$NativeBridge { *; }
-keepattributes *Annotation*
