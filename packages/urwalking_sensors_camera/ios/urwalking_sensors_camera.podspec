Pod::Spec.new do |s|
  s.name             = 'urwalking_sensors_camera'
  s.version          = '0.1.0'
  s.summary          = 'Camera frame capture and AR pose for urwalking_sensors.'
  s.description      = <<-DESC
AR pose tracking with ARKit for the urwalking_sensors library.
                       DESC
  s.homepage         = 'https://github.com/'
  s.license          = { :file => '../../../LICENSE' }
  s.author           = { 'urwalking team' => '' }
  s.source           = { :path => '.' }
  s.source_files = 'urwalking_sensors_camera/Sources/urwalking_sensors_camera/**/*.swift'
  s.dependency 'Flutter'
  s.frameworks = 'ARKit'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
