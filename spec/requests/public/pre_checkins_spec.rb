require "rails_helper"

RSpec.describe "Public::PreCheckins", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:booking) do
    create(
      :booking,
      hotel: hotel,
      guest_name: "Aisha Tan",
      guest_email: "aisha.tan@example.com",
      guest_phone: "+60123456789",
      guest_country: "Malaysia",
      guest_gender: "female",
      guest_document_type: "ic",
      guest_government_id: "900101-10-1234"
    )
  end
  let!(:pre_checkin) do
    create(:pre_checkin, booking: booking, status: "pending", document_status: "pending", signature_status: "pending")
  end

  describe "GET /pre-checkin/:token" do
    it "renders the form" do
      get pre_checkin_path(pre_checkin.token)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Complete your arrival details")
      expect(response.body).to include(booking.confirmation_token)
      expect(response.body).to include("guest_date_of_birth")
    end
  end

  describe "PATCH /pre-checkin/:token" do
    it "saves the missing details and marks the pre-check-in complete" do
      patch pre_checkin_path(pre_checkin.token), params: {
        booking: {
          guest_name: "Aisha Tan",
          guest_email: "aisha.tan@example.com",
          guest_phone: "+60123456789",
          guest_gender: "female",
          guest_country: "Malaysia",
          guest_document_type: "ic",
          guest_government_id: "900101-10-1234",
          estimated_arrival_time: "15:30",
          signature: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        }
      }

      expect(response).to redirect_to(pre_checkin_path(pre_checkin.token))

      expect(pre_checkin.reload.status).to eq("completed")
      expect(pre_checkin.completed_at).to be_present
      expect(pre_checkin.metadata["estimated_arrival_time"]).to eq("15:30")
      expect(booking.reload.pre_checkin_status).to eq("completed")
    end

    it "saves home address" do
      patch pre_checkin_path(pre_checkin.token), params: {
        booking: {
          guest_name: "Aisha Tan",
          guest_email: "aisha.tan@example.com",
          guest_phone: "+60123456789",
          guest_gender: "female",
          guest_country: "Malaysia",
          guest_document_type: "ic",
          guest_government_id: "900101-10-1234",
          guest_home_address: "No. 12, Jalan Ampang, 50450 Kuala Lumpur",
          estimated_arrival_time: "15:30",
          signature: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        }
      }

      expect(response).to redirect_to(pre_checkin_path(pre_checkin.token))
      expect(booking.reload.guest_home_address).to eq("No. 12, Jalan Ampang, 50450 Kuala Lumpur")
    end

    it "fails if signature is missing" do
      patch pre_checkin_path(pre_checkin.token), params: {
        booking: {
          guest_name: "Aisha Tan",
          guest_email: "aisha.tan@example.com",
          guest_phone: "+60123456789",
          guest_country: "Malaysia",
          estimated_arrival_time: "15:30"
        }
      }

      expect(pre_checkin.reload.status).not_to eq("completed")
      expect(response.body).to include("Guest signature is required.")
    end

    it "persists passport guest date of birth" do
      patch pre_checkin_path(pre_checkin.token), params: {
        booking: {
          guest_name: "Aisha Tan",
          guest_email: "aisha.tan@example.com",
          guest_phone: "+60123456789",
          guest_country: "Singapore",
          guest_document_type: "passport",
          guest_government_id: "P1234567",
          guest_date_of_birth: "1994-08-21",
          estimated_arrival_time: "15:30",
          signature: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        }
      }

      expect(response).to redirect_to(pre_checkin_path(pre_checkin.token))
      expect(booking.reload.primary_guest.date_of_birth).to eq(Date.new(1994, 8, 21))
    end

    it "fails cleanly when passport date of birth is missing" do
      patch pre_checkin_path(pre_checkin.token), params: {
        booking: {
          guest_name: "Aisha Tan",
          guest_email: "aisha.tan@example.com",
          guest_phone: "+60123456789",
          guest_country: "Singapore",
          guest_document_type: "passport",
          guest_government_id: "P1234567",
          guest_date_of_birth: "",
          estimated_arrival_time: "15:30",
          signature: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Date of birth is required for passport guests")
    end
  end
end
