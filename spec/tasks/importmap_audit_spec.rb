# frozen_string_literal: true

require "open3"
require "tmpdir"

# bin/importmap-audit must keep one promise: a network problem passes, a real
# vulnerability fails. These examples drive the script against stub binaries
# so no example touches the npm registry.
RSpec.describe "bin/importmap-audit" do
  let(:script) { File.expand_path("../../bin/importmap-audit", __dir__) }

  around do |example|
    Dir.mktmpdir { |dir| @stub_dir = dir; example.run }
  end

  # Writes a fake `importmap` binary that prints the given output and exits
  # with the given status.
  def stub_audit(output, exit_status: 0, sleep_for: nil)
    path = File.join(@stub_dir, "importmap")
    body = +"#!/usr/bin/env bash\n"
    body << "sleep #{sleep_for}\n" if sleep_for
    body << "cat <<'OUT'\n#{output}\nOUT\n"
    body << "exit #{exit_status}\n"
    File.write(path, body)
    File.chmod(0o755, path)
    path
  end

  def run(stub, timeout: 5, attempts: 2)
    env = {
      "IMPORTMAP_BIN" => stub,
      "IMPORTMAP_AUDIT_TIMEOUT" => timeout.to_s,
      "IMPORTMAP_AUDIT_ATTEMPTS" => attempts.to_s,
      "IMPORTMAP_AUDIT_RETRY_DELAY" => "0"
    }
    Open3.capture2e(env, script)
  end

  it "passes and shows the report when no package is vulnerable" do
    output, status = run(stub_audit("No vulnerable packages found"))

    expect(status).to be_success
    expect(output).to include("No vulnerable packages found")
  end

  it "fails and shows the report when a package is vulnerable" do
    report = "Package  Severity  Vulnerable versions\n" \
             "cally    high      <0.9.0\n" \
             "  1 vulnerability found: 1 high"

    output, status = run(stub_audit(report, exit_status: 1))

    expect(status).not_to be_success
    expect(status.exitstatus).to eq(1)
    expect(output).to include("1 vulnerability found")
  end

  it "passes when the registry returns a transport error" do
    error = "npm.rb:133: Unexpected error response 503: {\"error\":\"Service Unavailable\"} " \
            "(Importmap::Npm::HTTPError)"

    output, status = run(stub_audit(error, exit_status: 1))

    expect(status).to be_success
    expect(output).to include("returned a network error (attempt 1 of 2)")
    expect(output).to include("This is not a code failure")
  end

  it "passes when the registry hangs past the timeout" do
    output, status = run(stub_audit("", sleep_for: 30), timeout: 1)

    expect(status).to be_success
    expect(output).to include("timed out after 1s")
    expect(output).to include("This is not a code failure")
  end

  it "retries a transport error the configured number of times" do
    error = "Net::ReadTimeout with #<TCPSocket:(closed)>"

    output, = run(stub_audit(error, exit_status: 1), attempts: 3)

    expect(output).to include("attempt 1 of 3")
    expect(output).to include("attempt 2 of 3")
    expect(output).to include("attempt 3 of 3")
  end
end
