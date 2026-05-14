require "rails_helper"

RSpec.describe GuestArrival::ProcessPreCheckin do
  let(:booking) do
    create(
      :booking,
      pre_checkin_status: "pending",
      guest_country: "Singapore",
      guest_document_type: "passport",
      guest_email: "guest@example.com",
      guest_phone: "+60122222222"
    )
  end
  let(:pre_checkin) { create(:pre_checkin, booking: booking, status: "pending") }

  let(:params) do
    {
      "guest_name" => "Updated Guest",
      "guest_government_id" => "B7654321",
      "estimated_arrival_time" => "20:30"
    }
  end

  it "completes pre-checkin and links primary guest" do
    id_front = fixture_file_upload("sample_image.jpg", "image/jpeg")
    id_back = fixture_file_upload("sample_image.jpg", "image/jpeg")
    params_with_doc = params.merge("id_front" => id_front, "id_back" => id_back)
    
    result = described_class.new(booking: booking, pre_checkin: pre_checkin, params: params_with_doc).call

    expect(result.success?).to be(true)
    expect(pre_checkin.reload.status).to eq("completed")
    expect(pre_checkin.document_status).to eq("verified")
    expect(pre_checkin.signature_status).to eq("signed")
    expect(pre_checkin.metadata["guest_government_id"]).to eq("B7654321")
    expect(booking.reload.pre_checkin_status).to eq("completed")
    expect(booking.booking_guests.find_by(is_primary: true)).to be_present
    expect(booking.id_front).to be_attached
    expect(booking.id_back).to be_attached
  end

  it "returns failure when already completed" do
    pre_checkin.update!(status: "completed")

    result = described_class.new(booking: booking, pre_checkin: pre_checkin, params: params).call

    expect(result.success?).to be(false)
    expect(result.message).to include("already completed")
  end

  it "returns failure payload when booking update is invalid" do
    invalid_params = params.merge("guest_email" => "")

    result = described_class.new(booking: booking, pre_checkin: pre_checkin, params: invalid_params).call

    expect(result.success?).to be(false)
    expect(result.submitted_arrival_time).to eq("20:30")
    expect(result.submitted_government_id).to eq("B7654321")
    expect(pre_checkin.reload.status).to eq("pending")
  end
end
