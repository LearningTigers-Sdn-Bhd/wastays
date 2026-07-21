# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActiveStorage::Service::R2Service do
  let(:service) { described_class.new(bucket: "pending", region: "auto") }

  before do
    allow(AppConfig).to receive(:get).and_call_original
    allow(AppConfig).to receive(:get).with("r2_endpoint").and_return(nil)
    allow(AppConfig).to receive(:get).with("r2_bucket").and_return(nil)
  end

  it "falls back to the registered local disk service, not an unnamed instance, so signed URLs remain resolvable" do
    local_service = service.send(:local_service)

    expect(local_service).to be_a(ActiveStorage::Service::DiskService)
    expect(local_service.name).to eq(:local)
    expect(local_service).to equal(ActiveStorage::Blob.services.fetch(:local))
  end

  it "uploads and serves a file through the fallback without corrupting the service name in generated URLs" do
    key = "r2-fallback-spec-#{SecureRandom.hex(6)}"
    io = StringIO.new("hello")

    service.upload(key, io, checksum: Digest::MD5.base64digest("hello"))

    expect(service.exist?(key)).to be true

    ActiveStorage::Current.url_options = { host: "example.com" }
    url = service.url(key, expires_in: 5.minutes, filename: ActiveStorage::Filename.new("file.txt"), content_type: "text/plain", disposition: "inline")
    encoded_key = URI.parse(url).path.split("/")[-2]
    decoded = ActiveStorage.verifier.verified(encoded_key, purpose: :blob_key)

    expect(decoded["service_name"]).to eq("local")
  ensure
    ActiveStorage::Current.url_options = nil
    service.delete(key)
  end
end
