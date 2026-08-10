# NewPipeExtractor brings in Rhino to run YouTube's JavaScript. Rhino is built
# for the desktop JDK and references packages Android has never had. None of
# those code paths run here — the app only lists videos, it never asks Rhino to
# decipher a stream URL — so the references are silenced rather than stubbed.
#
# Listed as a group on purpose: R8 reports one package per build, and finding
# them one failed build at a time costs six minutes each.
-dontwarn javax.script.**
-dontwarn java.beans.**
-dontwarn java.lang.management.**
-dontwarn javax.annotation.**
-dontwarn javax.lang.model.**
-dontwarn javax.naming.**
-dontwarn javax.xml.**
-dontwarn org.w3c.dom.**
-dontwarn org.xml.sax.**
-dontwarn sun.misc.**
-dontwarn org.mozilla.javascript.**
-dontwarn org.schabi.newpipe.extractor.**

# Both lean on reflection, and a listing that breaks only in the release build
# is the worst kind of bug to chase when there is no way to build locally.
# A few megabytes of APK is the cheaper side of that trade.
-keep class org.mozilla.javascript.** { *; }
-keep class org.schabi.newpipe.extractor.** { *; }
