// Top-level build file for common configuration across all sub-projects/modules.
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // Firebase Gradle Plugin
        classpath("com.google.gms:google-services:4.4.2") // Fixed syntax: use parentheses
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Unified build directory configuration
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.set(newSubprojectBuildDir)
}

subprojects {
    evaluationDependsOn(":app")
}

// Clean task to delete build directory
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}