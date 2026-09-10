Pod::Spec.new do |s|
  s.name         = "RTLSdk"
  s.version      = "2.1.3"
  s.summary      = "Native iOS SDK for RTL platform integration."
  s.homepage     = "https://github.com/BOON-Rewards/rtl_ios_sdk"
  s.license      = { :type => "Proprietary" }
  s.authors      = { "BOON Rewards" => "support@getboon.com" }
  s.platforms    = { :ios => "15.0" }
  s.source       = { :git => "https://github.com/BOON-Rewards/rtl_ios_sdk.git", :tag => "#{s.version}" }
  s.source_files = "Sources/RTLSdk/**/*.{swift}"
  s.resource_bundles = {
    "RTLSdk" => ["Sources/RTLSdk/PrivacyInfo.xcprivacy"]
  }
  s.swift_version = "5.7"
end
