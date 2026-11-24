#!/usr/bin/env ruby
require 'xcodeproj'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'optparse'
require 'shellwords'

options = {}
OptionParser.new do |parser|
  parser.on('--source-ref REF') { |value| options[:ref] = value }
  parser.on('--device-id ID') { |value| options[:device] = value }
  parser.on('--work-dir DIR') { |value| options[:work_dir] = value }
end.parse!
abort 'Pass --device-id for a dedicated April Fools simulator.' unless options[:device]

root = File.expand_path('../../..', __dir__)
work = options[:work_dir] || Dir.mktmpdir('apriltag-overlay-uikit-')
FileUtils.mkdir_p(work)
source = File.join(root, 'native/ARCapture/AprilTagOverlayView.swift')
if options[:ref]
  content, stderr, status = Open3.capture3('git', '-C', root, 'show', "#{options[:ref]}:native/ARCapture/AprilTagOverlayView.swift")
  abort(stderr) unless status.success?
  source = File.join(work, 'AprilTagOverlayView.swift')
  File.write(source, content)
end

host_source = File.join(work, 'OverlayTestHost.swift')
File.write(host_source, <<~SWIFT)
  import UIKit
  @main
  class OverlayTestHost: UIResponder, UIApplicationDelegate {
      var window: UIWindow?
      func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
          let window = UIWindow(frame: UIScreen.main.bounds)
          window.rootViewController = UIViewController()
          window.rootViewController?.view.backgroundColor = .white
          window.makeKeyAndVisible()
          self.window = window
          return true
      }
  }
SWIFT

project = Xcodeproj::Project.new(File.join(work, 'OverlayRegression.xcodeproj'))
host = project.new_target(:application, 'OverlayTestHost', :ios, '17.0')
tests = project.new_target(:unit_test_bundle, 'OverlayRegressionTests', :ios, '17.0')
host.source_build_phase.add_file_reference(project.main_group.new_file(host_source))
[source, File.join(root, 'native/ARCapture/TagDebugMath.swift'), File.join(root, 'native/ARCapture/TagDebugPanelView.swift'),
 File.join(root, 'native/ARCapture/MetricGlossaryLabel.swift'), File.join(root, 'native/ARCapture/TagMetricGlossaryViewController.swift'),
 File.join(root, 'native/ARCapture/HeightDisplayFormatter.swift'), File.join(root, 'native/ARCapture/PreviewZoom.swift'),
 File.join(root, 'native/ARCapture/SpatialMeasurements.swift'), File.join(root, 'native/ARCapture/TagFloorHeight.swift'),
 File.join(root, 'native/ARCapture/TagCameraRanges.swift'),
 File.join(root, 'native/ARCapture/TagGravityOrientation.swift'),
 File.join(root, 'native/ARCapture/TagHeightVectors.swift'), File.join(root, 'native/ARCapture/FloorPlaneFit.swift'), File.join(root, 'native/ARCapture/FloorDepthSampler.swift'),
 File.join(root, 'native/ARCapture/FloorBaseMarker.swift'),
 File.join(root, 'native/ARCapture/SpatialProjection.swift'), File.join(root, 'native/ARCapture/SpatialMeasurementOverlayView.swift'),
 File.join(__dir__, 'AprilTagOverlayUIKitTests.swift'), File.join(__dir__, 'TagDebugMathTests.swift'),
 File.join(__dir__, 'TagFloorHeightTests.swift'), File.join(__dir__, 'TagCameraRangesTests.swift'), File.join(__dir__, 'HeightDisplayFormatterTests.swift'),
 File.join(__dir__, 'TagGravityOrientationTests.swift'),
 File.join(__dir__, 'TagHeightVectorsTests.swift'), File.join(__dir__, 'FloorLevelingTests.swift'), File.join(__dir__, 'FloorPlaneFitTests.swift'), File.join(__dir__, 'FloorDepthSamplerTests.swift'),
 File.join(__dir__, 'FloorBaseMarkerTests.swift'),
 File.join(__dir__, 'FloorBaseMarkerUIKitTests.swift'),
 File.join(root, 'native/SpatialMeasurementTests/SpatialMeasurementTests.swift'),
 File.join(root, 'native/SpatialMeasurementTests/SpatialProjectionUIKitTests.swift'),
 File.join(root, 'native/TagDebugPanelTests/TagDebugPanelUIKitTests.swift'),
 File.join(root, 'native/TagDebugPanelTests/TagMetricGlossaryUIKitTests.swift')].each do |path|
  tests.source_build_phase.add_file_reference(project.main_group.new_file(path))
end
glossary_resources = File.join(work, 'MetricGlossary')
system('ruby', File.join(root, 'scripts/bundle-metric-glossary.rb'), '--output', glossary_resources, exception: true)
glossary_reference = project.main_group.new_file(glossary_resources)
glossary_reference.last_known_file_type = 'folder'
host.resources_build_phase.add_file_reference(glossary_reference)
tests.add_dependency(host)
project.targets.each do |target|
  target.build_configurations.each do |config|
    settings = config.build_settings
    settings['SWIFT_VERSION'] = '5.0'
    settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    settings['PRODUCT_BUNDLE_IDENTIFIER'] = "org.aprilfoolsar.#{target.name}"
    settings['CODE_SIGNING_ALLOWED'] = 'NO'
    settings['SUPPORTED_PLATFORMS'] = 'iphonesimulator'
    settings['ENABLE_TESTABILITY'] = 'YES'
    settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone'
    if target == tests
      settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/OverlayTestHost.app/OverlayTestHost'
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
scheme.save_as(project.path, 'OverlayRegression')

command = ['xcodebuild', '-project', project.path.to_s, '-scheme', 'OverlayRegression', '-configuration', 'Debug',
           '-destination', "id=#{options[:device]}", '-derivedDataPath', File.join(work, 'DerivedData'),
           '-resultBundlePath', File.join(work, 'Results.xcresult'), '-parallel-testing-enabled', 'NO', 'test']
puts "Work directory: #{work}"
puts command.shelljoin
$stdout.flush
log = File.join(work, 'xcodebuild.log')
success = system(*command, out: log, err: [:child, :out])
puts File.readlines(log).select { |line| line.match?(/error:|Test Case|Executed |\*\* TEST|Testing failed|uncaught exception|NSInvalidArgumentException/) }.last(100).join
artifacts = File.join(work, 'artifacts')
FileUtils.mkdir_p(artifacts)
File.readlines(log).map { |line| line[/(?:OVERLAY|PANEL|GLOSSARY)_PNG[ =](.+\.png)/, 1] }.compact.uniq.each do |file|
  FileUtils.cp(file, artifacts) if File.file?(file)
end
puts "PNG artifacts: #{artifacts}"
puts "Full log: #{log}"
exit(success ? 0 : 1)
