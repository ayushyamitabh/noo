# Device sync (SyncWorker/ConflictResolveWorker) - WorkManager instantiates
# a lot of its own internals via reflection (Workers by class name recorded
# at enqueue time, its bundled Room database's *_Impl class off the
# abstract database class's own name, its default InputMerger, etc). R8's
# member-level shrinking silently breaks any of these - e.g. stripping an
# "unused" no-arg constructor - even when the class itself survives a
# plain `-keep class` with no wildcard, and narrowly keeping only the
# classes hit by one test pass just means the next reflection path (a
# different WorkManager-internal class) breaks instead. Two separate
# instances of this already bit real testing (WorkDatabase, then
# OverwritingInputMerger) before landing on this broad keep - see
# android/app/build.gradle.kts (androidx.work dependency) and
# .claude/context/server.md's "Device sync" section.
-keep class androidx.work.** { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class dev.ayushya.noo.SyncWorker { *; }
-keep class dev.ayushya.noo.ConflictResolveWorker { *; }
-keep class dev.ayushya.noo.SyncConflictReceiver { *; }
