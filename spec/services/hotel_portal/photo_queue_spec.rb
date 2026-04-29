# frozen_string_literal: true

require "rails_helper"
require "tempfile"

RSpec.describe HotelPortal::PhotoQueue, type: :service do
  let(:hotel) { create(:hotel) }
  let(:session) { {} }
  let(:service) { described_class.new(hotel, session) }

  def uploaded_file(filename, content_type, content = "dummy-content")
    file = Tempfile.new([ File.basename(filename, ".*"), File.extname(filename) ])
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, content_type, true, original_filename: filename)
  end

  let(:file) { uploaded_file("test_image.png", "image/png") }

  describe "#enqueue" do
    context "with a valid image" do
      it "enqueues the photo and returns success" do
        result = service.enqueue(file)
        expect(result[:success]).to be true
        expect(result[:blob]).to be_a(ActiveStorage::Blob)
        expect(session[:hotel_photo_queue][hotel.id.to_s]).to include(result[:blob].signed_id)
      end
    end

    context "with an invalid file type" do
      let(:invalid_file) { uploaded_file("test.txt", "text/plain") }

      it "returns an error" do
        result = service.enqueue(invalid_file)
        expect(result[:error]).to eq("Only image files are allowed.")
        expect(session[:hotel_photo_queue]).to be_nil
      end
    end

    context "when max photos limit is reached" do
      before do
        allow(service).to receive(:remaining_slots).and_return(0)
      end

      it "returns an error" do
        result = service.enqueue(file)
        expect(result[:error]).to include("reached the maximum")
      end
    end
  end

  describe "#remove" do
    it "removes a photo from the queue" do
      enqueue_result = service.enqueue(file)
      signed_id = enqueue_result[:blob].signed_id

      expect(service.remove(signed_id)).to be true
      expect(session[:hotel_photo_queue][hotel.id.to_s]).not_to include(signed_id)
    end

    it "returns false if the photo is not in the queue" do
      expect(service.remove("invalid_id")).to be false
    end
  end

  describe "#clear" do
    it "clears all photos from the queue" do
      service.enqueue(file)
      service.clear
      expect(session[:hotel_photo_queue][hotel.id.to_s]).to be_empty
    end
  end

  describe "#commit" do
    it "attaches queued photos to the hotel" do
      service.enqueue(file)
      expect {
        service.commit
      }.to change { hotel.photos.count }.by(1)
      expect(session[:hotel_photo_queue][hotel.id.to_s]).to be_empty
    end
  end

  describe "#summary" do
    it "returns the queue summary" do
      service.enqueue(file)
      summary = service.summary
      expect(summary[:queued_count]).to eq(1)
      expect(summary[:max_count]).to eq(Hotel::MAX_PHOTOS)
    end
  end
end
