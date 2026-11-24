# Shared numerical implementation and frame-explicit adapters for simulator bundles.
def add_spatial_core_to_test_target(project, target, root)
  Dir.glob(File.join(root, 'native/SpatialCore/src/*.cpp')).sort.each do |path|
    target.source_build_phase.add_file_reference(project.main_group.new_file(path))
  end
  %w[native/AprilTag/AFTagPoseConventions.c native/ARCapture/TagPoseReadout.swift
     native/ARCapture/TagDebugMath.swift native/ARCapture/FieldDefinitions.swift
     native/ARCapture/FieldTextCodec.swift].each do |relative|
    path = File.join(root, relative)
    next if target.source_build_phase.files_references.any? { |reference| reference.real_path.to_s == path }
    target.source_build_phase.add_file_reference(project.main_group.new_file(path))
  end
  target.build_configurations.each do |configuration|
    settings = configuration.build_settings
    settings['CLANG_CXX_LANGUAGE_STANDARD'] = 'c++17'
    settings['SWIFT_OBJC_BRIDGING_HEADER'] = File.join(root, 'native/SpatialCore/include/afsc.h')
    settings['HEADER_SEARCH_PATHS'] = ['$(inherited)', File.join(root, 'native/SpatialCore/include'), File.join(root, 'native/AprilTag')]
  end
end
