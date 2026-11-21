require 'xcodeproj'

root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'ios/AprilFoolsAR.xcodeproj'))
target = project.targets.find { |item| item.name == 'AprilFoolsAR' }
# Declare the generated JS bundle so Xcode signs it after every incremental build.
# Metro resolves the JS dependency graph itself, so this phase always runs.
bundle_phase = target.shell_script_build_phases.find { |phase| phase.name == 'Bundle React Native code and images' }
if bundle_phase
  bundle_phase.output_paths = ['$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/main.jsbundle']
  bundle_phase.always_out_of_date = '1'
end
native = project.main_group.groups.find { |group| group.name == 'Native' }
native ||= project.main_group.new_group('Native', '../native')
Dir.glob(File.join(root, 'native/**/*.{swift,m,mm,c}')).sort.each do |path|
  next if path.downcase.include?('/tests/') || File.basename(path).downcase.include?('test')
  relative = path.delete_prefix(File.join(root, 'native/'))
  reference = native.files.find { |file| file.path == relative } || native.new_file(relative)
  target.source_build_phase.add_file_reference(reference, true)
end
vendor = project.main_group.groups.find { |group| group.name == 'AprilTag upstream' }
vendor ||= project.main_group.new_group('AprilTag upstream', '../third_party/apriltag')
File.readlines(File.join(root, 'third_party/apriltag/sources.txt'), chomp: true).reject(&:empty?).each do |relative|
  raise "Missing AprilTag source: #{relative}" unless File.file?(File.join(root, 'third_party/apriltag', relative))
  reference = vendor.files.find { |file| file.path == relative } || vendor.new_file(relative)
  target.source_build_phase.add_file_reference(reference, true)
end
%w[LICENSE.md NOTICE.md].each do |name|
  next unless File.exist?(File.join(root, 'third_party/apriltag', name))
  reference = vendor.files.find { |file| file.path == name } || vendor.new_file(name)
  target.resources_build_phase.add_file_reference(reference, true)
end
target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.doughorner.aprilfoolsar'
  config.build_settings['DEVELOPMENT_TEAM'] = 'X5873NL7XM'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['MARKETING_VERSION'] = '0.1.0'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '3'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['SWIFT_OBJC_BRIDGING_HEADER'] = '$(SRCROOT)/../native/AprilFoolsAR-Bridging-Header.h'
  config.build_settings['HEADER_SEARCH_PATHS'] = ['$(inherited)', '$(SRCROOT)/../native', '$(SRCROOT)/../third_party/apriltag']
  config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
end
project.root_object.attributes['TargetAttributes'] ||= {}
project.root_object.attributes['TargetAttributes'][target.uuid] ||= {}
project.root_object.attributes['TargetAttributes'][target.uuid]['DevelopmentTeam'] = 'X5873NL7XM'
project.root_object.attributes['TargetAttributes'][target.uuid]['ProvisioningStyle'] = 'Automatic'
project.save
puts "Configured #{target.name}; #{target.source_build_phase.files.count} sources"
