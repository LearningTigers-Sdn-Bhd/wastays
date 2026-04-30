# frozen_string_literal: true

require 'rails_helper'

RSpec.describe HotelPortal::PhotoQueueService do
  let(:session) { {} }
  let(:hotel) { create(:hotel) }
  let(:service) { described_class.new(session, hotel) }
  let(:file) do
    Rack::Test::UploadedFile.new(
      Rails.root.join('spec/fixtures/files/sample_image.jpg'),
      'image/jpeg'
    )
  end

  before do
    # Ensure fixture exists
    FileUtils.mkdir_p(Rails.root.join('spec/fixtures/files'))
    File.write(Rails.root.join('spec/fixtures/files/sample_image.jpg'), 'fake image content')
  end

  describe '#enqueue' do
    it 'adds a blob to the queue' do
      expect {
        service.enqueue(file)
      }.to change { service.queued_count }.by(1)
    end

    it 'returns error if file is blank' do
      result = service.enqueue(nil)
      expect(result[:error]).to eq("Please choose at least one image.")
    end
  end

  describe '#remove' do
    it 'removes a blob from the queue' do
      result = service.enqueue(file)
      signed_id = result[:blob].signed_id

      expect {
        service.remove(signed_id)
      }.to change { service.queued_count }.by(-1)
    end
  end

  describe '#clear' do
    it 'clears the queue' do
      service.enqueue(file)
      service.clear
      expect(service.queued_count).to eq(0)
    end
  end
end
