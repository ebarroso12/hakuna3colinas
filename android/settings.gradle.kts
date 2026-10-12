pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
    // Processa o `google-services.json`. SEM ELE o arquivo e ignorado em
    // SILENCIO: o app compila, instala, e `Firebase.initializeApp()`
    // falha em tempo de execucao — que o try/catch do `main` engole. O
    // push simplesmente nao existiria e nada no build acusaria.
    id("com.google.gms.google-services") version "4.5.0" apply false
}

include(":app")
