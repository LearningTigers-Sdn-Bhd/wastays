# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::RoomTypes::DestroyPhotos do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:photo) do
    fixture_file_upload(Rails.root.join("spec/fixtures/files/sample_image.jpg"), "image/jpeg")
  end

  before do
    room_type.photos.attach(photo)
  end

  describe "#call" do
    context "with valid photo_ids" do
      let(:photo_id) { room_type.photos.first.id }
      subject { described_class.new(room_type: room_type, photo_ids: [ photo_id ]) }

      it "destroys the specified photos" do
        expect {
          result = subject.call
          expect(result.success?).to be true
        }.to change { room_type.photos.count }.by(-1)
      end
    end

    context "with multiple photo_ids" do
      before do
        room_type.photos.attach(fixture_file_upload(Rails.root.join("spec/fixtures/files/sample_image.jpg"), "image/jpeg"))
      end

      let(:photo_ids) { room_type.photos.pluck(:id) }
      subject { described_class.new(room_type: room_type, photo_ids: photo_ids) }

      it "destroys all specified photos" do
        expect {
          result = subject.call
          expect(result.success?).to be true
        }.to change { room_type.photos.count }.to(0)
      end
    end

    context "with empty photo_ids" do
      subject { described_class.new(room_type: room_type, photo_ids: []) }

      it "returns failure" do
        result = subject.call
        expect(result.success?).to be false
        expect(result.message).to eq("No photos selected.")
      end
    end

    context "with invalid photo_ids" do
      subject { described_class.new(room_type: room_type, photo_ids: [ 0 ]) }

      it "returns failure" do
        result = subject.call
        expect(result.success?).to be false
        expect(result.message).to eq("Photos not found.")
      end
    end
  end
end
