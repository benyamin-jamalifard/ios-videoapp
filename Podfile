# Google Cast ships through CocoaPods only. Run `pod install` after
# `xcodegen generate`, then open KelaketFilm.xcworkspace.
platform :ios, '16.0'

target 'KelaketFilm' do
  use_frameworks!
  pod 'google-cast-sdk', '~> 4.8'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
    end
  end
end
