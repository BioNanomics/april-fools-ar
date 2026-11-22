#!/usr/bin/env ruby
require 'xcodeproj'
require 'tmpdir'
require 'fileutils'
require 'optparse'
require 'shellwords'

options = { device: 'DBE3B4F0-0581-4B4F-B693-17FEC5753C55' }
OptionParser.new do |parser|
  parser.on('--device-id ID') { |value| options[:device] = value }
  parser.on('--work-dir DIR') { |value| options[:work_dir] = value }
end.parse!
root = File.expand_path('../../..', __dir__)
work = options[:work_dir] || Dir.mktmpdir('aprilfools-build-info-')
FileUtils.mkdir_p(work)
host_source = File.join(work, 'BuildInfoTestHost.swift')
File.write(host_source, <<~SWIFT)
  import UIKit
  @main
  class BuildInfoTestHost: UIResponder, UIApplicationDelegate {
      var window: UIWindow?
      func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
          let window = UIWindow(frame: UIScreen.main.bounds)
          window.rootViewController = UIViewController()
          window.makeKeyAndVisible()
          self.window = window
          return true
      }
  }
SWIFT
# The recorder only reads this provenance constant. Camera/detection are not exercised here.
detector_stub = File.join(work, 'RecorderDetectorProvenance.swift')
File.write(detector_stub, "enum AFTagDetector { static func upstreamRevision() -> String { \"fixture-detector-provenance\" } }\n")
project = Xcodeproj::Project.new(File.join(work, 'BuildInfoRegression.xcodeproj'))
host = project.new_target(:application, 'BuildInfoTestHost', :ios, '17.0')
tests = project.new_target(:unit_test_bundle, 'BuildInfoRegressionTests', :ios, '17.0')
host.source_build_phase.add_file_reference(project.main_group.new_file(host_source))
['AppBuildInfo.swift', 'CaptureRecorder.swift', 'TagDebugMath.swift'].map { |file| File.join(root, 'native/ARCapture', file) }
  .concat([detector_stub, File.join(__dir__, 'AppBuildInfoTests.swift')]).each do |path|
    tests.source_build_phase.add_file_reference(project.main_group.new_file(path))
  end
tests.add_dependency(host)
project.targets.each do |target|
  target.build_configurations.each do |configuration|
    settings = configuration.build_settings
    settings['SWIFT_VERSION'] = '5.0'
    settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    settings['PRODUCT_BUNDLE_IDENTIFIER'] = "org.aprilfoolsar.#{target.name}"
    settings['CODE_SIGNING_ALLOWED'] = 'NO'
    settings['SUPPORTED_PLATFORMS'] = 'iphonesimulator'
    settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone'
    if target == tests
      settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/BuildInfoTestHost.app/BuildInfoTestHost'
      settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
    end
  end
end
load File.join(root, 'scripts/spatial-core-xcode.rb')
add_spatial_core_to_test_target(project, tests, root)
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(host)
scheme.add_test_target(tests)
scheme.set_launch_target(host)
scheme.test_action.build_configuration = 'Debug'
scheme.save_as(project.path, 'BuildInfoRegression')
command = ['xcodebuild', '-project', project.path.to_s, '-scheme', 'BuildInfoRegression', '-configuration', 'Debug',
  '-destination', "id=#{options[:device]}", '-derivedDataPath', File.join(work, 'DerivedData'),
  '-resultBundlePath', File.join(work, 'Results.xcresult'), '-parallel-testing-enabled', 'NO', 'test']
puts "Work directory: #{work}"
puts command.shelljoin
$stdout.flush
log = File.join(work, 'xcodebuild.log')
success = system(*command, out: log, err: [:child, :out])
puts File.readlines(log).select { |line| line.match?(/error:|Test Case|Executed |\*\* TEST|Testing failed|uncaught exception/) }.last(80).join
puts "Full log: #{log}"
exit(success ? 0 : 1)
