allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// maplibre_gl configures its Kotlin compiler through the `kotlin { }` extension,
// and from AGP 9 it deliberately stops applying the Kotlin Gradle Plugin itself
// (its own comment cites Flutter #905). That is only safe when AGP supplies
// Kotlin instead -- and the Flutter app template explicitly sets
// `android.builtInKotlin=false`, so it does not. The plugin's build script then
// dies on `Could not find method kotlin()` before a line of our code compiles.
//
// Applied to that one module rather than by flipping the global flag: every
// other plugin here applies KGP for itself, and `builtInKotlin=true` would put
// AGP's Kotlin and theirs in the same module. Hooked on `com.android.library`
// because KGP refuses to apply before an Android plugin is present.
//
// It also compiles itself at Java 21 while this app, every other plugin here and
// the JDK Flutter is configured with are all 17, so javac stops at
// `invalid source release: 21`. Pulled back to 17 rather than moving the whole
// machine to a newer JDK: the plugin's sources use no language feature past 8,
// and one homogeneous toolchain is worth more than its declared floor.
//
// Registered from here, not from inside the `withPlugin` callback, so this
// `afterEvaluate` is queued before AGP queues its own -- it has to overwrite
// what the plugin's script sets, and be read by AGP when it builds variants.
subprojects {
    if (name == "maplibre_gl") {
        pluginManager.withPlugin("com.android.library") {
            pluginManager.apply("org.jetbrains.kotlin.android")
        }
        afterEvaluate {
            extensions
                .findByType(com.android.build.api.dsl.LibraryExtension::class.java)
                ?.compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            extensions
                .findByType(
                    org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension::class.java,
                )
                ?.compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                }
        }
    }
}
