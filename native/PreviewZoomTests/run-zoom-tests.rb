#!/usr/bin/env ruby
require 'xcodeproj'
require 'tmpdir'
require 'fileutils'
require 'optparse'
require 'shellwords'

options={}
OptionParser.new do |parser|
  parser.on('--device-id ID') { |value| options[:device]=value }
  parser.on('--work-dir DIR') { |value| options[:work_dir]=value }
end.parse!
abort 'Pass --device-id for a dedicated April Fools simulator.' unless options[:device]
root=File.expand_path('../..',__dir__)
work=options[:work_dir] || Dir.mktmpdir('aprilfools-preview-zoom-')
FileUtils.mkdir_p(work)
host_source=File.join(work,'ZoomTestHost.swift')
File.write(host_source,<<~SWIFT)
  import UIKit
  @main
  class ZoomTestHost:UIResponder,UIApplicationDelegate {
      var window:UIWindow?
      func application(_ application:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]?)->Bool {
          let window=UIWindow(frame:UIScreen.main.bounds)
          window.rootViewController=UIViewController()
          window.makeKeyAndVisible(); self.window=window
          return true
      }
  }
SWIFT
project=Xcodeproj::Project.new(File.join(work,'PreviewZoomRegression.xcodeproj'))
host=project.new_target(:application,'ZoomTestHost',:ios,'17.0')
tests=project.new_target(:unit_test_bundle,'PreviewZoomRegressionTests',:ios,'17.0')
host.source_build_phase.add_file_reference(project.main_group.new_file(host_source))
['native/ARCapture/PreviewZoom.swift','native/ARCapture/AprilTagOverlayView.swift',
 'native/ARCapture/HeightDisplayFormatter.swift',
 'native/ARCapture/TagDebugMath.swift','native/PreviewZoomTests/PreviewZoomUIKitTests.swift'].each do |relative|
  tests.source_build_phase.add_file_reference(project.main_group.new_file(File.join(root,relative)))
end
tests.add_dependency(host)
project.targets.each do |target|
  target.build_configurations.each do |config|
    settings=config.build_settings
    settings['SWIFT_VERSION']='5.0'
    settings['GENERATE_INFOPLIST_FILE']='YES'
    settings['PRODUCT_BUNDLE_IDENTIFIER']="org.aprilfoolsar.#{target.name}"
    settings['CODE_SIGNING_ALLOWED']='NO'
    settings['SUPPORTED_PLATFORMS']='iphonesimulator'
    settings['ENABLE_TESTABILITY']='YES'
    settings['TARGETED_DEVICE_FAMILY']='1,2'
    settings['SWIFT_OPTIMIZATION_LEVEL']='-Onone'
    if target==tests
      settings['TEST_HOST']='$(BUILT_PRODUCTS_DIR)/ZoomTestHost.app/ZoomTestHost'
      settings['BUNDLE_LOADER']='$(TEST_HOST)'
    end
  end
end
load File.join(root, 'scripts/spatial-core-xcode.rb')
add_spatial_core_to_test_target(project, tests, root)
project.save
scheme=Xcodeproj::XCScheme.new
scheme.add_build_target(host); scheme.add_test_target(tests); scheme.set_launch_target(host)
scheme.test_action.build_configuration='Debug'
scheme.save_as(project.path,'PreviewZoomRegression')
command=['xcodebuild','-project',project.path.to_s,'-scheme','PreviewZoomRegression','-configuration','Debug',
 '-destination',"id=#{options[:device]}",'-derivedDataPath',File.join(work,'DerivedData'),
 '-resultBundlePath',File.join(work,'Results.xcresult'),'-parallel-testing-enabled','NO','test']
puts "Work directory: #{work}"
puts command.shelljoin
$stdout.flush
log=File.join(work,'xcodebuild.log')
success=system(*command,out:log,err:[:child,:out])
puts File.readlines(log).select { |line| line.match?(/error:|Test Case|Executed |\*\* TEST|Testing failed|uncaught exception/) }.last(100).join
puts "Full log: #{log}"
exit(success ? 0 : 1)
