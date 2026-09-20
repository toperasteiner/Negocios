import java.util.Properties


plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter plugin deve vir depois de Android/Kotlin
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase/Play Services (se usar):
    id("com.google.gms.google-services")
}

// Lê android/keystore.properties (se existir)
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("keystore.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}



println("🔐 storeFile = ${keystoreProperties["storeFile"]}")
println("🔐 keyAlias  = ${keystoreProperties["keyAlias"]}")

android {
    namespace = "br.com.danielsousa.pedidos"

    // Você pode fixar em 34, mas deixei o do Flutter como no seu arquivo:
    compileSdk = 36

    // NDK exigido pelos plugins (o seu valor):
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "br.com.danielsousa.pedidos"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                val storeFilePath = keystoreProperties["storeFile"] as String?
                if (!storeFilePath.isNullOrBlank()) {
                    storeFile = file(storeFilePath)
                }
                storePassword = keystoreProperties["storePassword"] as String?
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
            } else {
                // fallback: evita quebrar localmente se não houver keystore
                println("⚠️  keystore.properties não encontrado. O build de release usará assinatura de debug.")
            }
        }
    }

    buildTypes {
        getByName("release") {
            // Se houver keystore.properties, usa release; senão, cai para debug
            signingConfig = if (keystorePropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")

            // Otimizações de release
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        getByName("debug") {
            // nada especial
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Exemplo (adicione o que precisar):
    // implementation("androidx.multidex:multidex:2.0.1")
}
