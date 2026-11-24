#!/usr/bin/env ruby
require 'xcodeproj'
require 'tmpdir'
require 'fileutils'
require 'optparse'
require 'shellwords'
require 'json'
require 'open3'

# This harness never addresses physical devices. Without --device-id it owns a
# new disposable simulator and deletes it on both successful and failed runs.
options = {}
OptionParser.new do |parser|
  parser.on('--device-id ID', 'Use an existing simulator owned by the caller') { |value| options[:device] = value }
  parser.on('--work-dir DIR') { |value| options[:work_dir] = value }
  parser.on('--only-testing TEST', 'Run one target/class/test selector (repeatable)') { |value| (options[:only_testing] ||= []) << value }
end.parse!
root = File.expand_path('../../..', __dir__)
work = File.expand_path(options[:work_dir] || Dir.mktmpdir('april-recording-tests-'))
FileUtils.mkdir_p(work)

def simctl_json(*args)
  output, status = Open3.capture2('xcrun', 'simctl', *args, '--json')
  abort "simctl #{args.join(' ')} failed" unless status.success?
  JSON.parse(output)
end

owned_simulator = nil
test_pid = nil
%w[INT TERM].each do |signal|
  Signal.trap(signal) do
    Process.kill('TERM', -test_pid) if test_pid
    exit 130
  rescue Errno::ESRCH
    exit 130
  end
end

begin
  if options[:device]
    simulators = simctl_json('list', 'devices', 'available').fetch('devices').values.flatten
    abort '--device-id must identify an available simulator; physical devices are unsupported.' unless simulators.any? { |device| device['udid'] == options[:device] }
  else
    runtimes = simctl_json('list', 'runtimes').fetch('runtimes').select { |runtime| runtime['isAvailable'] && runtime['identifier'].include?('.iOS-') }
    runtime = runtimes.max_by { |item| item.fetch('version').split('.').map(&:to_i) }
    abort 'No available iOS simulator runtime.' unless runtime
    types = simctl_json('list', 'devicetypes').fetch('devicetypes')
    type = types.find { |item| item['name'] == 'iPhone 17 Pro' } || types.reverse.find { |item| item['name'].start_with?('iPhone') }
    abort 'No iPhone simulator device type.' unless type
    output, status = Open3.capture2('xcrun', 'simctl', 'create', "Recording modes #{Process.pid}", type.fetch('identifier'), runtime.fetch('identifier'))
    abort 'Could not create the dedicated recording test simulator.' unless status.success?
    owned_simulator = output.strip
    options[:device] = owned_simulator
  end

  host_source = File.join(work, 'RecordingTestHost.swift')
  File.write(host_source, <<~SWIFT)
    import UIKit
    @main class RecordingTestHost: UIResponder, UIApplicationDelegate {
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
  detector_stub = File.join(work, 'RecorderDetectorProvenance.swift')
  File.write(detector_stub, "enum AFTagDetector { static func upstreamRevision() -> String { \"recording-test-provenance\" } }\n")
  project = Xcodeproj::Project.new(File.join(work, 'RecordingRegression.xcodeproj'))
  host = project.new_target(:application, 'RecordingTestHost', :ios, '17.0')
  tests = project.new_target(:unit_test_bundle, 'RecordingModeTests', :ios, '17.0')
  host.source_build_phase.add_file_reference(project.main_group.new_file(host_source))
  %w[
    native/ARCapture/RecordingCapacity.swift
    native/ARCapture/SavedFieldWalk.swift
    native/ARCapture/CaptureRecorder.swift
    native/ARCapture/AppBuildInfo.swift
    native/ARCapture/SpatialProjection.swift
    native/ArchiveModule/SessionMP4Writer.swift
    native/ArchiveModule/SavedRecordingStore.swift
    native/ArchiveModule/VideoOrientation.swift
    native/ARCapture/tests/RecordingModeTests.swift
  ].map { |relative| File.join(root, relative) }.concat([detector_stub]).each do |path|
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
        settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/RecordingTestHost.app/RecordingTestHost'
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
  scheme.save_as(project.path, 'RecordingRegression')
  command = ['xcodebuild', '-project', project.path.to_s, '-scheme', 'RecordingRegression', '-configuration', 'Debug',
    '-destination', "id=#{options[:device]}", '-derivedDataPath', File.join(work, 'DerivedData'),
    '-resultBundlePath', File.join(work, 'Results.xcresult'), '-parallel-testing-enabled', 'NO', 'test']
  options.fetch(:only_testing, []).each { |selector| command << "-only-testing:#{selector}" }
  log = File.join(work, 'xcodebuild.log')
  puts "Work directory: #{work}"
  puts "Simulator: #{options[:device]}#{owned_simulator ? ' (owned, deleted on exit)' : ' (caller owned)'}"
  puts command.shelljoin
  $stdout.flush
  test_pid = Process.spawn(*command, out: log, err: [:child, :out], pgroup: true)
  _, status = Process.wait2(test_pid)
  test_pid = nil
  puts File.readlines(log).select { |line| line.match?(/error:|Test Case|Executed |\*\* TEST|Testing failed|uncaught exception/) }.last(120).join
  puts "Full log: #{log}"
  exit(status.success? ? 0 : 1)
ensure
  if test_pid
    begin
      Process.kill('TERM', -test_pid)
      Process.wait(test_pid)
    rescue Errno::ESRCH, Errno::ECHILD
      # A signal handler or xcodebuild may already have ended the child.
    end
  end
  if owned_simulator
    system('xcrun', 'simctl', 'shutdown', owned_simulator, out: File::NULL, err: File::NULL)
    deleted = system('xcrun', 'simctl', 'delete', owned_simulator)
    unless deleted
      warn "Could not delete owned simulator #{owned_simulator}"
      exit 1
    end
    puts "Deleted owned simulator: #{owned_simulator}"
  end
end
