# NewPipeExtractor pulls in Rhino to run YouTube's JavaScript. Rhino ships an
# optional JSR-223 wrapper that imports javax.script — a package Android does
# not have. Nothing here uses it, so silence the reference instead of shipping
# a stub for it.
-dontwarn javax.script.**
-dontwarn org.mozilla.javascript.engine.**

# Both libraries lean on reflection, and a listing that fails only in release
# builds is the worst kind of bug to chase. Keeping them costs a little size
# and removes the whole class of problem.
-keep class org.mozilla.javascript.** { *; }
-keep class org.schabi.newpipe.extractor.** { *; }
-dontwarn org.schabi.newpipe.extractor.**
