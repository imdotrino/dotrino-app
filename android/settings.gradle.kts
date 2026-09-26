pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "dotrino-app"
include(":app")
// La librería nativa del ecosistema: el repo dotrino-native, como submódulo en ../native.
includeBuild("../native/android")
