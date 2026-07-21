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
// Certains plugins (file_picker, flutter_plugin_android_lifecycle) exigent de
// compiler contre l'API 36. On force donc compileSdk >= 36 sur tous les modules
// Android APRÈS leur configuration, sans quoi `checkDebugAarMetadata` échoue.
// Ce bloc est déclaré AVANT `evaluationDependsOn` pour que le `afterEvaluate`
// soit enregistré avant toute évaluation forcée.
subprojects {
    afterEvaluate {
        (extensions.findByName("android") as? com.android.build.gradle.BaseExtension)?.apply {
            val current =
                compileSdkVersion?.removePrefix("android-")?.toIntOrNull() ?: 0
            if (current < 36) {
                compileSdkVersion(36)
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
