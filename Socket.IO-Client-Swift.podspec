Pod::Spec.new do |s|
  s.name         = "Socket.IO-Client-Swift"
  s.module_name  = "SocketIO"
  s.version      = "17.0.0-native.1"
  s.summary      = "Socket.IO-client for iOS and OS X"
  s.description  = <<-DESC
                   Socket.IO-client for iOS and OS X.
                   Supports ws/wss/polling connections and binary.
                   For Socket.IO 4.x and Swift 6.4 (Swift 6 language mode).
                   DESC
  s.homepage     = "https://github.com/kaeferfreund/socket.io-client-swift"
  s.license      = { :type => 'MIT' }
  s.author       = { "Erik" => "nuclear.ace@gmail.com" }
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.tvos.deployment_target = '15.0'
  s.watchos.deployment_target = '9.0'
  s.requires_arc = true
  s.source = {
    :git => "https://github.com/kaeferfreund/socket.io-client-swift.git",
    # Development prerelease. Use an immutable tag before publishing.
    :branch => 'master'
  }

  s.swift_version = "6.0"
  s.pod_target_xcconfig = {
      'SWIFT_VERSION' => '6.0'
  }
  s.source_files  = "Source/SocketIO/**/*.swift", "Source/SocketIO/*.swift"
end
