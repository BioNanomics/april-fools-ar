#!/usr/bin/env ruby
require 'xcodeproj'
require 'tmpdir'
require 'fileutils'
require 'optparse'
require 'shellwords'
require 'open3'
require 'json'

options = { only_testing: [] }
OptionParser.new do |parser|
  parser.on('--work-dir DIR') { |value| options[:work_dir] = value }
  parser.on('--app-path PATH') { |value| options[:app_path] = value }
  parser.on('--only-testing ID') { |value| options[:only_testing] << value }
end.parse!
root = File.expand_path('../..',__dir__)
work = options[:work_dir] || Dir.mktmpdir('april-field-app-ui-')
FileUtils.mkdir_p(work)
device = nil
begin
  unless options[:app_path]
    node, _, node_status = Open3.capture3('node','--version')
    abort 'Put a working Node 22+ binary first on PATH before running this harness.' unless node_status.success? && node[/\d+/].to_i >= 22
    build_log = File.join(work,'app-build.log')
    build = ['xcodebuild','-workspace',File.join(root,'ios/AprilFoolsAR.xcworkspace'),'-scheme','AprilFoolsAR',
      '-configuration','Release','-destination','generic/platform=iOS Simulator',
      '-derivedDataPath',File.join(work,'AppDerivedData'),'CODE_SIGNING_ALLOWED=NO','ONLY_ACTIVE_ARCH=YES',"ARCHS=#{`uname -m`.strip}",'build']
    puts "Building actual Release app: #{build.shelljoin}"; $stdout.flush
    abort "Release simulator build failed; see #{build_log}" unless system(*build,chdir:root,out:build_log,err:[:child,:out])
    options[:app_path] = File.join(work,'AppDerivedData/Build/Products/Release-iphonesimulator/AprilFoolsAR.app')
  end
  abort 'App bundle is missing.' unless File.directory?(options[:app_path])
  abort 'Release app does not contain embedded JavaScript.' unless File.size?(File.join(options[:app_path],'main.jsbundle'))
  device_output,device_error,device_status = Open3.capture3('xcrun','simctl','create','April Field App UI','com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro','com.apple.CoreSimulator.SimRuntime.iOS-26-0')
  abort device_error unless device_status.success?
  device = device_output.strip
  system('xcrun','simctl','boot',device,exception:true,out:File::NULL)
  system('xcrun','simctl','bootstatus',device,'-b',exception:true,out:File::NULL)
  system('xcrun','simctl','install',device,options[:app_path],exception:true)
  project = Xcodeproj::Project.new(File.join(work,'FieldAppUITests.xcodeproj'))
  tests = project.new_target(:ui_test_bundle,'FieldAppUITests',:ios,'17.0')
  tests.source_build_phase.add_file_reference(project.main_group.new_file(File.join(__dir__,'FieldAppUITests.swift')))
  tests.build_configurations.each do |configuration|
    s = configuration.build_settings
    s['SWIFT_VERSION'] = '5.0'
    s['GENERATE_INFOPLIST_FILE'] = 'YES'
    s['PRODUCT_BUNDLE_IDENTIFIER'] = 'org.aprilfoolsar.FieldAppUITests'
    s['CODE_SIGNING_ALLOWED'] = 'NO'
    s['SUPPORTED_PLATFORMS'] = 'iphonesimulator'
    s['TARGETED_DEVICE_FAMILY'] = '1,2'
  end
  project.save
  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(tests);scheme.add_test_target(tests)
  scheme.test_action.build_configuration = 'Debug'
  scheme.save_as(project.path,'FieldAppUITests')
  command = ['xcodebuild','-project',project.path.to_s,'-scheme','FieldAppUITests','-configuration','Debug',
    '-destination',"id=#{device}",'-derivedDataPath',File.join(work,'TestDerivedData'),
    '-resultBundlePath',File.join(work,'Results.xcresult'),'-parallel-testing-enabled','NO']
  command.concat(options[:only_testing].map { |identifier| "-only-testing:#{identifier}" })
  command << 'test'
  log = File.join(work,'xcodebuild.log')
  puts "Executing native app UI checks: #{command.shelljoin}"; $stdout.flush
  success = system(*command,out:log,err:[:child,:out])
  puts File.readlines(log).select { |line| line.match?(/error:|Test Case|Executed |\*\* TEST|Testing failed|uncaught exception/) }.last(100).join
  artifacts = File.join(work,'artifacts');FileUtils.mkdir_p(artifacts)
  system('xcrun','xcresulttool','export','attachments','--path',File.join(work,'Results.xcresult'),'--output-path',artifacts,out:File::NULL,err:File::NULL)
  manifest = File.join(artifacts,'manifest.json')
  if File.file?(manifest)
    JSON.parse(File.read(manifest)).flat_map { |test| test.fetch('attachments',[]) }.each do |attachment|
      source = File.join(artifacts,attachment.fetch('exportedFileName'))
      next unless File.file?(source) && %w[.png .txt].include?(File.extname(source))
      label = attachment.fetch('suggestedHumanReadableName','').split('_0_').first.to_s
      next unless label.start_with?('field-')
      name = label.gsub(/[^a-zA-Z0-9_-]/,'-') + File.extname(source)
      FileUtils.cp(source,File.join(artifacts,name))
    end
  end
  puts "UI evidence: #{artifacts}"
  puts "Full log: #{log}"
  exit(success ? 0 : 1)
ensure
  if device
    system('xcrun','simctl','shutdown',device,out:File::NULL,err:File::NULL)
    removed = system('xcrun','simctl','delete',device,out:File::NULL,err:File::NULL)
    puts(removed ? 'Owned UI test simulator deleted.' : 'Owned UI simulator cleanup failed; inspect simctl before handoff.')
  end
end
