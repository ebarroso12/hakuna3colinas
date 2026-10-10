import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// ASSINATURA DE RELEASE
//
// Duas fontes, nesta ordem:
//   1. android/key.properties  — maquina do desenvolvedor (NO .gitignore)
//   2. variaveis de ambiente   — CI (GitHub Actions, via secrets)
//
// Nenhuma das duas vai para o git. O keystore (.jks) tambem nao: perder o
// arquivo e irreversivel, e quem o tiver pode publicar atualizacao em nome
// do app, entao ele mora no cofre do usuario e nos secrets do GitHub.
//
// Se NENHUMA das duas existir, o release continua assinando com a chave de
// debug — e e isso que acontece hoje. Nao e um acidente aqui: e o fallback
// que mantem `flutter build apk --release` funcionando sem keystore. O
// APK resultante instala por "fontes desconhecidas" (que e o fluxo de
// distribuicao por Drive) e NAO serve para a Play Store.
//
// AVISO que precisa ser dito antes de trocar: assinar com chave nova muda
// a identidade do app para o Android. Quem ja tem o legendarios1.0.x
// instalado vai ter de DESINSTALAR antes de atualizar — a atualizacao por
// cima falha com INSTALL_FAILED_UPDATE_INCOMPATIBLE. Decidir isso e do
// usuario, nao meu, e por isso o fallback existe em vez de uma troca seca.
// ---------------------------------------------------------------------------

val propriedadesDaChave = Properties().apply {
    val arquivo = rootProject.file("key.properties")
    if (arquivo.exists()) arquivo.inputStream().use { load(it) }
}

/** Le de key.properties e, se faltar, da variavel de ambiente do CI. */
fun chave(nome: String, variavelDeAmbiente: String): String? =
    propriedadesDaChave.getProperty(nome)?.takeIf { it.isNotBlank() }
        ?: System.getenv(variavelDeAmbiente)?.takeIf { it.isNotBlank() }

val caminhoKeystore = chave("storeFile", "LEGENDARIOS_KEYSTORE_PATH")
val senhaKeystore = chave("storePassword", "LEGENDARIOS_KEYSTORE_PASSWORD")
val aliasChave = chave("keyAlias", "LEGENDARIOS_KEY_ALIAS")
val senhaChave = chave("keyPassword", "LEGENDARIOS_KEY_PASSWORD")

/**
 * So assina de producao quando as QUATRO coisas existem E o arquivo esta
 * la. Config pela metade e pior que nenhuma: o Gradle falha no fim do
 * build, depois de minutos, com erro de keystore em vez de dizer o que
 * falta.
 */
val temChaveDeProducao = caminhoKeystore != null &&
    senhaKeystore != null &&
    aliasChave != null &&
    senhaChave != null &&
    file(caminhoKeystore).exists()

android {
    namespace = "com.legendarios.hakuna_connect"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.legendarios.hakuna_connect"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (temChaveDeProducao) {
            create("release") {
                storeFile = file(caminhoKeystore!!)
                storePassword = senhaKeystore
                keyAlias = aliasChave
                keyPassword = senhaChave
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (temChaveDeProducao) {
                signingConfigs.getByName("release")
            } else {
                // Fallback explicito. Ver o bloco de ASSINATURA no topo.
                signingConfigs.getByName("debug")
            }
        }
    }
}

// Diz em qual chave o build saiu. Sem isto, descobrir que um APK de
// homologacao foi assinado com chave de debug exige rodar `apksigner` no
// arquivo — e normalmente alguem descobre depois de distribuir.
tasks.register("qualChaveDeAssinatura") {
    group = "verification"
    doLast {
        println(
            if (temChaveDeProducao) {
                "Release sera assinado com a chave de PRODUCAO: $caminhoKeystore"
            } else {
                "Release sera assinado com a chave de DEBUG " +
                    "(key.properties ausente e sem variaveis de ambiente). " +
                    "Instala por fontes desconhecidas; nao serve para Play Store."
            }
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
