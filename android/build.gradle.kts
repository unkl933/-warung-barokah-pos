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

// Injeksi namespace dan paksa compileSdk ke versi 34
subprojects {
    plugins.withId("com.android.library") {
        val android = extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
        if (android != null) {
            // Paksa compileSdk minimal 34 agar kompatibel dengan library AndroidX terbaru
            if (android.compileSdk == null || (android.compileSdk ?: 0) < 34) {
                android.compileSdk = 34
            }

            // Injeksi namespace khusus plugin
            if (project.name == "blue_thermal_printer") {
                android.namespace = "id.kakzaki.blue_thermal_printer"
            } else if (android.namespace == null) {
                android.namespace = "com.plugin.${project.name.replace("-", "_")}"
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

