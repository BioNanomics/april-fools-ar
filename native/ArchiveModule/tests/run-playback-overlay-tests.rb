#!/usr/bin/env ruby
require 'xcodeproj'
require 'tmpdir'
require 'fileutils'
require 'optparse'
require 'shellwords'

options = { only_testing: [] }
OptionParser.new do |parser|
  parser.on('--device-id ID', 'Dedicated task-owned simulator UUID (required)') { |value| options[:device] = value }
  parser.on('--work-dir DIR') { |value| options[:work_dir] = value }
  parser.on('--only-testing ID') { |value| options[:only_testing] << value }
  parser.on('--recording-folder DIR', 'Optional private capture metadata folder; never copied into the repository') { |value| options[:recording_folder] = value }
  parser.on('--recording-video FILE', 'Optional matching upright MP4 for the private playback check') { |value| options[:recording_video] = value }
end.parse!
abort 'Pass --device-id for a dedicated April Fools simulator.' unless options[:device]
abort 'Pass both --recording-folder and --recording-video.' if !!options[:recording_folder] != !!options[:recording_video]

root = File.expand_path('../../..', __dir__)
work = options[:work_dir] || Dir.mktmpdir('aprilfools-playback-overlay-')
FileUtils.mkdir_p(work)
host_source = File.join(work, 'PlaybackOverlayTestHost.swift')
File.write(host_source, <<~SWIFT)
  import UIKit
  @main
  class PlaybackOverlayTestHost: UIResponder, UIApplicationDelegate {
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

project = Xcodeproj::Project.new(File.join(work, 'PlaybackOverlayRegression.xcodeproj'))
host = project.new_target(:application, 'PlaybackOverlayTestHost', :ios, '17.0')
tests = project.new_target(:unit_test_bundle, 'PlaybackOverlayRegressionTests', :ios, '17.0')
host.source_build_phase.add_file_reference(project.main_group.new_file(host_source))

sources = [
  'native/ArchiveModule/VideoOrientation.swift',
  'native/ArchiveModule/RecordingPreview.swift',
  'native/ARCapture/SpatialMeasurements.swift',
  'native/ARCapture/SpatialProjection.swift',
  'native/ARCapture/HeightDisplayFormatter.swift',
  'native/ArchiveModule/tests/RecordingPreviewTests.swift',
  'native/ArchiveModule/tests/VideoOrientationTests.swift',
  'native/ArchiveModule/tests/RecordingPlaybackOverlayTests.swift',
].map { |relative| File.join(root, relative) }
sources.concat(Dir.glob(File.join(root, 'native/ArchiveModule/RecordingPlayback*.swift')).sort)
sources.concat(Dir.glob(File.join(root, 'native/ArchiveModule/tests/RecordingPlayback*Tests.swift')).sort)
sources.uniq.each do |source|
  abort "Missing playback source: #{source}" unless File.file?(source)
  tests.source_build_phase.add_file_reference(project.main_group.new_file(source))
end
if options[:recording_folder]
  fixture = File.join(work, 'recorded-fixture')
  FileUtils.mkdir_p(fixture)
  %w[manifest.json frames.jsonl events.jsonl].each do |name|
    source = File.join(options[:recording_folder], name)
    abort "Missing private capture metadata: #{name}" unless File.file?(source)
    FileUtils.cp(source, File.join(fixture, name))
  end
  abort 'Missing private playback movie.' unless File.file?(options[:recording_video])
  FileUtils.cp(options[:recording_video], File.join(fixture, 'recording.mp4'))
  resource = project.main_group.new_file(fixture)
  resource.last_known_file_type = 'folder'
  tests.resources_build_phase.add_file_reference(resource)
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
    settings['ENABLE_TESTABILITY'] = 'YES'
    settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone'
    settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES' if target == host
    if target == tests
      settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/PlaybackOverlayTestHost.app/PlaybackOverlayTestHost'
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
scheme.save_as(project.path, 'PlaybackOverlayRegression')
command = ['xcodebuild', '-project', project.path.to_s, '-scheme', 'PlaybackOverlayRegression',
  '-configuration', 'Debug', '-destination', "id=#{options[:device]}",
  '-derivedDataPath', File.join(work, 'DerivedData'), '-resultBundlePath', File.join(work, 'Results.xcresult'),
  '-parallel-testing-enabled', 'NO']
command.concat(options[:only_testing].map { |identifier| "-only-testing:#{identifier}" })
command << 'test'
puts "Work directory: #{work}"
puts command.shelljoin
$stdout.flush
log = File.join(work, 'xcodebuild.log')
success = system(*command, out: log, err: [:child, :out])
puts File.readlines(log).select { |line| line.match?(/error:|Test Case|Executed |\*\* TEST|Testing failed|uncaught exception/) }.last(120).join
puts "Full log: #{log}"
artifacts = File.join(work, 'artifacts')
FileUtils.mkdir_p(artifacts)
File.readlines(log).map { |line| line[/PLAYBACK_OVERLAY_PNG (.+\.png)/, 1] }.compact.uniq.each do |file|
  FileUtils.cp(file, artifacts) if File.file?(file)
end
puts "Screenshot artifacts: #{artifacts}"
exit(success ? 0 : 1)
