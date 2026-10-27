# Run with: ruby .github/scripts/test_ios_version.rb
require "yaml"
require "tmpdir"
require "open3"

workflow = YAML.load_file(File.expand_path("../workflows/ios.yml", __dir__))
steps = workflow.fetch("jobs").fetch("publish").fetch("steps")
channel_step = steps.find { |item| item["id"] == "channel" }.fetch("run")
version_step = steps.find { |item| item["id"] == "version" }.fetch("run")

def run_step(script, dir:, env:)
  output = File.join(dir, "output")
  File.write(output, "")
  log, status = Open3.capture2e(
    { "GITHUB_OUTPUT" => output }.merge(env),
    "bash", "-c", script, chdir: dir
  )
  [status.success?, File.read(output), log]
end

def git(dir, *args)
  output, status = Open3.capture2e("git", "-C", dir, *args)
  raise "git #{args.join(' ')} failed: #{output}" unless status.success?

  output.strip
end

def assert_channel(script, dir:, before:, expected:, event: "push", manual: "")
  success, output, log = run_step(
    script, dir: dir, env: {
      "EVENT_NAME" => event,
      "MANUAL_CHANNEL" => manual,
      "PUSH_BEFORE" => before
    }
  )
  if expected
    raise "channel #{event}/#{manual}: #{log}\n#{output}" unless success && output == "value=#{expected}\n"
  else
    raise "channel #{event}/#{manual}: invalid version was accepted" if success
  end
end

Dir.mktmpdir("hinata-ios-version-") do |dir|
  fastlane = File.join(dir, "fastlane")
  File.write(fastlane, "#!/bin/bash\necho NEXT_BUILD_NUMBER=123\n")
  File.chmod(0755, fastlane)

  # Verify that iOS marketing versions and Apple build numbers are independent.
  %w[beta production].each do |channel|
    %w[2.6.0+11 2.6.1+12 2.6.9+13 invalid].each do |version|
      File.write(File.join(dir, "pubspec.yaml"), "version: #{version}\n")
      success, output, log = run_step(
        version_step, dir: dir, env: {
          "PATH" => "#{dir}:#{ENV.fetch('PATH')}",
          "RELEASE_CHANNEL" => channel
        }
      )
      if version == "invalid"
        raise "#{channel}: accepted an invalid version" if success
        next
      end

      project_version = version.split("+").first
      major, minor, patch = project_version.split(".").map(&:to_i)
      marketing = channel == "beta" ? "#{major}.#{minor}.#{patch + 1}" : project_version
      expected = "marketing=#{marketing}\nbuild=123\n"
      raise "#{channel}/#{version}: #{log}\n#{output}" unless success && output == expected
    end
  end

  # Mimic pushes on main. The stable tag must be taken from the commit before
  # the push, even if the Android release job tags the new HEAD concurrently.
  git(dir, "init", "-q")
  git(dir, "config", "user.name", "CI test")
  git(dir, "config", "user.email", "ci@example.invalid")
  File.write(File.join(dir, "pubspec.yaml"), "version: 2.8.0+13\n")
  git(dir, "add", "pubspec.yaml")
  git(dir, "commit", "-qm", "Release 2.8.0")
  git(dir, "tag", "v2.8.0")
  before_beta = git(dir, "rev-parse", "HEAD")
  git(dir, "commit", "--allow-empty", "-qm", "No version change")
  assert_channel(channel_step, dir: dir, before: before_beta, expected: "beta")

  before_release = git(dir, "rev-parse", "HEAD")
  File.write(File.join(dir, "pubspec.yaml"), "version: 2.8.1+13\n")
  git(dir, "add", "pubspec.yaml")
  git(dir, "commit", "-qm", "Release 2.8.1")
  assert_channel(channel_step, dir: dir, before: before_release, expected: "production")
  git(dir, "tag", "v2.8.1")
  assert_channel(channel_step, dir: dir, before: before_release, expected: "production")

  before_next_beta = git(dir, "rev-parse", "HEAD")
  git(dir, "commit", "--allow-empty", "-qm", "Next test build")
  assert_channel(channel_step, dir: dir, before: before_next_beta, expected: "beta")
  assert_channel(channel_step, dir: dir, before: "", expected: "production",
                 event: "workflow_dispatch", manual: "production")
  assert_channel(channel_step, dir: dir, before: "", expected: "beta",
                 event: "workflow_dispatch", manual: "beta")
  assert_channel(channel_step, dir: dir, before: "", expected: nil,
                 event: "workflow_dispatch", manual: "unsupported")

  File.write(File.join(dir, "pubspec.yaml"), "version: 2.7.9+13\n")
  assert_channel(channel_step, dir: dir, before: before_next_beta, expected: nil)
  File.write(File.join(dir, "pubspec.yaml"), "version: invalid\n")
  assert_channel(channel_step, dir: dir, before: before_next_beta, expected: nil)
end

puts "iOS version checks passed: unchanged versions increment only for TestFlight; new stable versions remain exact."
