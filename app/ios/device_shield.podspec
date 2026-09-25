#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint device_shield.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'device_shield'
  s.version          = '0.0.1'
  s.summary          = 'Runtime device-security checks for Flutter apps.'
  s.description      = <<-DESC
Jailbreak, simulator, debugger and mock-location detection, plus screen
capture protections, for the device_shield Flutter plugin.
                       DESC
  s.homepage         = 'https://github.com/Vikaskumar75/device-shield'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'GeekyAnts' => 'vikas@geekyants.com' }
  s.source           = { :path => '.' }
  s.source_files = 'device_shield/Sources/device_shield/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # Declares no tracking, no collected data and no required-reason APIs.
  # Update it if a detector starts using one (e.g. file timestamps,
  # UserDefaults, system boot time).
  s.resource_bundles = {'device_shield_privacy' => ['device_shield/Sources/device_shield/PrivacyInfo.xcprivacy']}
end
