#!/usr/bin/env ruby
require 'xcodeproj'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'optparse'
require 'shellwords'
require 'json'

options = {}
trap('TERM') { raise Interrupt }
OptionParser.new do |parser|
  parser.on('--app-path PATH') { |value| options[:app] = File.expand_path(value) }
  parser.on('--work-dir DIR') { |value| options[:work] = File.expand_path(value) }
  parser.on('--derived-data-path DIR') { |value| options[:derived_data] = File.expand_path(value) }
end.parse!
abort 'Pass --app-path for a built Release-iphonesimulator AprilFoolsAR.app.' unless options[:app] && File.directory?(options[:app])
work = options[:work] || Dir.mktmpdir('april-thumb-reach-')
FileUtils.mkdir_p(work)

def execute(*args)
  output, status = Open3.capture2e(*args)
  abort "#{args.shelljoin}\n#{output}" unless status.success?
  output
end

device = nil
begin
  app_info = JSON.parse(execute('plutil', '-convert', 'json', '-o', '-', File.join(options[:app], 'Info.plist')))
  device = execute('xcrun', 'simctl', 'create', "April Fools Thumb Reach #{Process.pid}",
                   'com.apple.CoreSimulator.SimDeviceType.iPhone-17', 'com.apple.CoreSimulator.SimRuntime.iOS-26-0').strip
  File.write(File.join(work, 'simulator-id.txt'), device + "\n")
  execute('xcrun', 'simctl', 'boot', device)
  execute('xcrun', 'simctl', 'bootstatus', device, '-b')
  execute('xcrun', 'simctl', 'install', device, options[:app])

  project = Xcodeproj::Project.new(File.join(work, 'ThumbReach.xcodeproj'))
  tests = project.new_target(:ui_test_bundle, 'ThumbReachUITests', :ios, '17.0')
  tests.source_build_phase.add_file_reference(project.main_group.new_file(File.join(__dir__, 'ThumbReachUITests.swift')))
  tests.build_configurations.each do |config|
    config.build_settings.merge!({
      'SWIFT_VERSION' => '5.0', 'GENERATE_INFOPLIST_FILE' => 'YES',
      'PRODUCT_BUNDLE_IDENTIFIER' => 'org.aprilfoolsar.ThumbReachUITests',
      'CODE_SIGNING_ALLOWED' => 'NO', 'SUPPORTED_PLATFORMS' => 'iphonesimulator',
      'TARGETED_DEVICE_FAMILY' => '1,2', 'SWIFT_OPTIMIZATION_LEVEL' => '-Onone'
    })
  end
  project.save
  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(tests)
  scheme.add_test_target(tests)
  scheme.test_action.build_configuration = 'Debug'
  scheme.test_action.environment_variables = Xcodeproj::XCScheme::EnvironmentVariables.new([
    { key: 'THUMB_EXPECTED_VERSION', value: app_info.fetch('CFBundleShortVersionString') },
    { key: 'THUMB_EXPECTED_BUILD', value: app_info.fetch('CFBundleVersion') }
  ])
  scheme.test_action.should_use_launch_scheme_args_env = false
  scheme.save_as(project.path, 'ThumbReach')

  command = ['xcodebuild', '-project', project.path.to_s, '-scheme', 'ThumbReach', '-configuration', 'Debug',
             '-destination', "id=#{device}", '-derivedDataPath', options[:derived_data] || File.join(work, 'DerivedData'),
             '-resultBundlePath', File.join(work, 'Results.xcresult'), '-parallel-testing-enabled', 'NO', 'test']
  puts "Dedicated simulator: #{device}\n#{command.shelljoin}"
  $stdout.flush
  log = File.join(work, 'xcodebuild.log')
  success = system(*command, out: log, err: [:child, :out])
  puts File.readlines(log).select { |line| line.match?(/error:|Test Case|Executed |\*\* TEST|THUMB_FRAMES|THUMB_SIDE|THUMB_INFO|THUMB_NAV|THUMB_VERSION|THUMB_PNG|THUMB_SCREEN|Testing failed/) }.last(120).join
  artifacts = File.join(work, 'artifacts')
  FileUtils.mkdir_p(artifacts)
  File.readlines(log).map { |line| line[/THUMB_PNG (.+\.png)/, 1] }.compact.uniq.each do |file|
    FileUtils.cp(file, artifacts) if File.file?(file)
  end
  puts "Artifacts: #{artifacts}\nFull log: #{log}"
  exit(success ? 0 : 1)
ensure
  if device
    system('xcrun', 'simctl', 'terminate', device, 'com.bionanomics.aprilfoolsar', out: File::NULL, err: File::NULL)
    system('xcrun', 'simctl', 'shutdown', device, out: File::NULL, err: File::NULL)
    system('xcrun', 'simctl', 'delete', device, out: File::NULL, err: File::NULL)
    puts "Cleaned up dedicated simulator #{device}"
  end
end
