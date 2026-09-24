# frozen_string_literal: true

require "rails_helper"

RSpec.describe AroundThat::TestConnection do
  let(:base_url) { "https://api.aroundthat.test/v1" }
  let(:probe_url) { "#{base_url}/places" }

  def service(**overrides)
    described_class.new(api_key: "at-key", base_url: base_url, environment: "staging", **overrides)
  end

  it "reports missing settings before it makes a request" do
    expect(service(base_url: "").call.message).to eq("Base URL is missing.")
    expect(service(api_key: "").call.message).to eq("API key is missing.")
  end

  it "rejects a base URL that is not an http address" do
    result = service(base_url: "ftp://files.aroundthat.test").call

    expect(result).not_to be_success
    expect(result.message).to eq("Base URL must be an http or https address.")
  end

  it "sends the API key as a bearer token" do
    request = stub_request(:get, probe_url)
      .with(headers: { "Authorization" => "Bearer at-key", "Accept" => "application/json" })
      .to_return(status: 200, body: "{}")

    service.call

    expect(request).to have_been_requested
  end

  it "succeeds on a 2xx and names the host and environment" do
    stub_request(:get, probe_url).to_return(status: 200, body: "{}")

    result = service.call

    expect(result).to be_success
    expect(result.message).to eq("AroundThat answered at api.aroundthat.test (staging).")
  end

  it "reports a rejected key on 401 and 403" do
    stub_request(:get, probe_url).to_return(status: 401)
    expect(service.call.message).to eq("AroundThat reached api.aroundthat.test, but rejected the API key.")

    stub_request(:get, probe_url).to_return(status: 403)
    expect(service.call.message).to eq("AroundThat reached api.aroundthat.test, but rejected the API key.")
  end

  it "names the probe path on a 404" do
    stub_request(:get, probe_url).to_return(status: 404)

    result = service.call

    expect(result).not_to be_success
    expect(result.message).to include("/v1/places returned 404")
  end

  it "asks the probe endpoint, not the base URL" do
    request = stub_request(:get, probe_url).to_return(status: 200, body: "{}")

    service.call

    expect(request).to have_been_requested
  end

  it "joins the probe path when the base URL ends with a slash" do
    request = stub_request(:get, probe_url).to_return(status: 200, body: "{}")

    service(base_url: "#{base_url}/").call

    expect(request).to have_been_requested
  end

  it "reports any other status code" do
    stub_request(:get, probe_url).to_return(status: 503)

    expect(service.call.message).to eq("AroundThat reached api.aroundthat.test, but returned HTTP 503.")
  end

  it "shows the message AroundThat sent for a bad credential" do
    stub_request(:get, probe_url).to_return(
      status: 401,
      body: { error: { code: "invalid_credential", message: "The integration credential is not valid." } }.to_json
    )

    result = service.call

    expect(result).not_to be_success
    expect(result.message).to eq(
      "AroundThat refused the request: The integration credential is not valid. (invalid_credential)"
    )
  end

  it "shows the message AroundThat sent for a missing capability" do
    stub_request(:get, probe_url).to_return(
      status: 403,
      body: { error: { code: "capability_required", message: "The integration cannot perform this operation." } }.to_json
    )

    expect(service.call.message).to include("cannot perform this operation", "capability_required")
  end

  it "keeps the status message when the body is not an error document" do
    stub_request(:get, probe_url).to_return(status: 503, body: "<html>gateway</html>")

    expect(service.call.message).to eq("AroundThat reached api.aroundthat.test, but returned HTTP 503.")
  end

  it "reports a network failure instead of raising" do
    stub_request(:get, probe_url).to_timeout

    result = service.call

    expect(result).not_to be_success
    expect(result.message).to start_with("Connection failed:")
  end

  it "falls back to the stored settings when nothing is passed" do
    AppConfig.set("aroundthat_api_key", "stored-key")
    AppConfig.set("aroundthat_base_url", base_url)
    AppConfig.set("aroundthat_environment", "production")

    request = stub_request(:get, probe_url)
      .with(headers: { "Authorization" => "Bearer stored-key" })
      .to_return(status: 200, body: "{}")

    expect(described_class.new.call.message).to include("(production)")
    expect(request).to have_been_requested
  end
end
