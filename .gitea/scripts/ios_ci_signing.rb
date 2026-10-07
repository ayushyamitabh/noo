# CI-only: switches the Release configuration of the Runner and ShareExtension
# targets to manual signing with the App Store profiles. The committed project
# stays on Automatic signing so local development is unaffected; this edit
# happens only inside the CI checkout. Run from the repo root:
#   ruby .gitea/scripts/ios_ci_signing.rb
require "xcodeproj"

TEAM = "Q3JLTAG9PV"
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
    settings["CODE_SIGN_IDENTITY"] = "Apple Distribution"
    settings["CODE_SIGN_IDENTITY[sdk=iphoneos*]"] = "Apple Distribution"
    settings["PROVISIONING_PROFILE_SPECIFIER"] = profile
  end
end
project.save
