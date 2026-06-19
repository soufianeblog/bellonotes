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
// Force plugin modules to compile against a recent enough Android SDK.
// Some plugins (e.g. file_picker, flutter_plugin_android_lifecycle) require compileSdk 36+.
// Registered before evaluationDependsOn(":app") so the afterEvaluate hook is in place
// before any subproject triggers evaluation.
subprojects {
    afterEvaluate {
        project.extensions.findByType(com.android.build.api.dsl.CommonExtension::class.java)?.let { ext ->
            if ((ext.compileSdk ?: 0) < 36) {
                ext.compileSdk = 36
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
