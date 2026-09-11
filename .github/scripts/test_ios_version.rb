# Run with: ruby .github/scripts/test_ios_version.rb
require "yaml"
require "tmpdir"
require "open3"

workflow = YAML.load_file(File.expand_path("../workflows/ios.yml", __dir__))
step = workflow.fetch("jobs").fetch("publish").fetch("steps").find { |item| item["id"] == "version" }

Dir.mktmpdir("hinata-ios-version-") do |dir|
  fastlane = File.join(dir, "fastlane")
  File.write(fastlane, "#!/bin/bash\necho NEXT_BUILD_NUMBER=123\n")
  File.chmod(0755, fastlane)
  output = File.join(dir, "output")

  %w[beta production].each do |channel|
    %w[2.6.0+11 2.6.1+12 invalid].each do |version|
      File.write(File.join(dir, "pubspec.yaml"), "version: #{version}\n")
      File.write(output, "")
      log, status = Open3.capture2e(
        { "PATH" => "#{dir}:#{ENV.fetch('PATH')}", "GITHUB_OUTPUT" => output, "RELEASE_CHANNEL" => channel },
        "bash", "-c", step.fetch("run"), chdir: dir
      )
      if version == "invalid"
        raise "#{channel}: accepted an invalid version" if status.success?
      else
        marketing = {
          "beta" => { "2.6.0+11" => "2.6.1", "2.6.1+12" => "2.6.2" },
          "production" => { "2.6.0+11" => "2.6.0", "2.6.1+12" => "2.6.1" }
        }.fetch(channel).fetch(version)
        expected = "marketing=#{marketing}\nbuild=123\n"
        raise "#{channel}/#{version}: #{log}\n#{File.read(output)}" unless status.success? && File.read(output) == expected
      end
    end
  end
end

puts "iOS version checks passed: TestFlight advances one patch; production preserves the project version."
