# CI-only: switches the Release configuration of the Runner and ShareExtension
# targets to manual signing with the App Store profiles. The committed project
# stays on Automatic signing so local development is unaffected; this edit
# happens only inside the CI checkout. Run from the repo root:
#   ruby .gitea/scripts/ios_ci_signing.rb
require "xcodeproj"

TEAM = "Q3JLTAG9PV"
# Pinned by SHA-1, not by the "Apple Distribution" name: a runner that also
# holds other same-named distribution certs (e.g. a dev Mac's login keychain)
# would otherwise let Xcode pick one the profiles don't include. Update this
# (and ios/ExportOptions.plist) when the certificate is renewed.
CERT_SHA1 = "2527806871D806E8E27221B15CA8A1938CF216F2"
PROFILES = {
  "Runner" => "NooProfile",
  "ShareExtension" => "NooShareSheetProfile",
}.freeze

project = Xcodeproj::Project.open("ios/Runner.xcodeproj")
PROFILES.each do |target_name, profile|
  target = project.targets.find { |t| t.name == target_name } or abort("no target #{target_name}")
  target.build_configurations.select { |c| c.name == "Release" }.each do |config|
    settings = config.build_settings
    settings["CODE_SIGN_STYLE"] = "Manual"
    settings["DEVELOPMENT_TEAM"] = TEAM
    settings["CODE_SIGN_IDENTITY"] = CERT_SHA1
    settings["CODE_SIGN_IDENTITY[sdk=iphoneos*]"] = CERT_SHA1
    settings["PROVISIONING_PROFILE_SPECIFIER"] = profile
  end
end
project.save
