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

// Paksa compileSdk ke 34 dan injeksi namespace dengan aman
subprojects {
    plugins.withId("com.android.library") {
        val android = extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
        if (android != null) {
            // Menaikkan compileSdk agar kompatibel dengan AndroidX terbaru
            android.compileSdk = 34

            // Injeksi namespace plugin
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

