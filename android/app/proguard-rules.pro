# R8 rules for Locus Planner.
#
# Flutter registers plugins statically, but several plugins use reflection for
# platform views, ML Kit tasks and home-screen widgets. Keep their entry points
# and the app's own classes; shrink everything else.

-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.locusplanner.app.** { *; }
-keep class org.sqlite.** { *; }
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class es.antonborri.home_widget.** { *; }

-dontwarn io.flutter.embedding.**
-dontwarn org.sqlite.**
-dontwarn com.google.mlkit.**
