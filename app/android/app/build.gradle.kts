import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名从 `android/key.properties` 读取 —— 该文件**不进仓库**（见 .gitignore），
// 也绝不要把 keystore 或密码提交上来。
//
// 文件不存在时回落到 debug 签名：这样没配签名的人仍然能跑 `flutter run --release`，
// 但 release 产物会被所有商店拒收，所以下面会打印一条显式警告。
// 生成步骤见 docs/release-checklist.md 或运行 tool/gen-upload-keystore.sh。
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.sdknwdtvpv.lianleme"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.sdknwdtvpv.lianleme"
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
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // 没有 key.properties 时回落到 debug 签名，好处是 `flutter run --release`
            // 对没配签名的人仍然可用。但**产物会被商店拒收**，所以下面挂了硬检查。
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
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

// ── release 产物的签名硬检查 ────────────────────────────────────────────────
//
// `flutter build` 会过滤掉 Gradle 的 logger.warn，所以**只警告等于没警告** ——
// 你会静默拿到一个商店必然拒收的 debug 签名包。按本仓库一贯的"不假装通过"，
// 这里改成产出 release 之前直接失败。
//
// 用 taskGraph.whenReady 而不是某个 task 的 doFirst：后者在任务 up-to-date 时
// 根本不执行，会留下"旧产物已经被 debug 签名过"的漏网情况。
//
// 确实需要 debug 签名的 release 包（例如跑性能测试）时：
//     ORG_GRADLE_PROJECT_allowDebugSigning=true flutter build appbundle --release
val allowDebugSigning =
    (providers.gradleProperty("allowDebugSigning").orNull ?: "false").toBoolean()

gradle.taskGraph.whenReady {
    val wantsReleaseArtifact = allTasks.any {
        it.name == "bundleRelease" || it.name == "assembleRelease"
    }
    if (wantsReleaseArtifact && !hasReleaseSigning && !allowDebugSigning) {
        throw GradleException(
            """
            ✗ 找不到 app/android/key.properties —— release 产物将使用 debug 签名，商店一定会拒收。

              生成正式签名：
                  cd app/android && ./tool/gen-upload-keystore.sh

              步骤与上架前置清单：docs/release-checklist.md

              确实需要 debug 签名（如性能测试）时：
                  ORG_GRADLE_PROJECT_allowDebugSigning=true flutter build appbundle --release
            """.trimIndent(),
        )
    }
}
