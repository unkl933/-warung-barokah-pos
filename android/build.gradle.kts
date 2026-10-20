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

// Injeksi namespace otomatis dan bypass error AAR metadata untuk plugin lama
subprojects {
    afterEvaluate {
        val androidExtension = extensions.findByName("android")
        if (androidExtension != null) {
            try {
                val namespaceProp = androidExtension.javaClass.getMethod("getNamespace")
                val currentNamespace = namespaceProp.invoke(androidExtension)
                if (currentNamespace == null) {
                    val setNamespace = androidExtension.javaClass.getMethod("setNamespace", String::class.java)
                    if (project.name == "blue_thermal_printer") {
                        setNamespace.invoke(androidExtension, "id.kakzaki.blue_thermal_printer")
                    } else {
                        setNamespace.invoke(androidExtension, "com.plugin.${project.name.replace("-", "_")}")
                    }
                }
            } catch (e: Exception) {
                // Lewati jika properti namespace tidak ditemukan
            }
        }
    }
    
    // Menonaktifkan pemeriksaan AAR metadata agar tidak memblokir build akibat perbedaan versi SDK
    tasks.matching { it.name.contains("AarMetadata") }.configureEach {
        enabled = false
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

