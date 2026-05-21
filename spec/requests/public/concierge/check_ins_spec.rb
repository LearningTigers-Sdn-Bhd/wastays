require "rails_helper"

RSpec.describe "Public::Concierge::CheckIns", type: :request do
  let(:hotel) { create(:hotel, status: "live", concierge_enabled: true) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:booking) do
    b = create(:booking, hotel: hotel, guest_name: "Ahmad Zulkifli", status: "confirmed",
               check_in: Date.today, check_out: Date.today + 1)
    b.booking_rooms.create!(room_type: room_type, quantity: 1, subtotal: 200,
                             room_type_snapshot: { "name" => room_type.name })
    b
  end

  before { Rails.cache.clear }

  describe "GET /concierge/:hotel_slug/check-in" do
    it "renders the chooser page" do
      get concierge_check_in_path(hotel.slug)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("I have a booking")
    end
  end

  describe "POST /concierge/:hotel_slug/check-in/lookup" do
    context "pre-checkin not completed" do
      before do
        hotel.create_property_policy!(check_in_time: "14:00", check_out_time: "12:00")
      end

      it "redirects to pre-checkin form" do
        post concierge_check_in_lookup_path(hotel.slug),
             params: { confirmation_token: booking.confirmation_token }
        expect(response).to redirect_to(pre_checkin_path(booking.reload.pre_checkin.token))
      end
    end

    context "pre-checkin already completed" do
      before do
        booking.create_pre_checkin!(status: "completed", document_status: "verified",
                                    signature_status: "signed", completed_at: Time.current)
      end

      it "redirects to check-in now page" do
        post concierge_check_in_lookup_path(hotel.slug),
             params: { confirmation_token: booking.confirmation_token }
        expect(response).to redirect_to(concierge_check_in_now_path(hotel.slug))
      end
    end

    it "re-renders with error on unknown token" do
      post concierge_check_in_lookup_path(hotel.slug),
           params: { confirmation_token: "WS-XXXXXXXX" }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /concierge/:hotel_slug/check-in/now" do
    before do
      booking.create_pre_checkin!(status: "completed", document_status: "verified",
                                  signature_status: "signed", completed_at: Time.current)
      post concierge_check_in_lookup_path(hotel.slug),
           params: { confirmation_token: booking.confirmation_token }
    end

    context "room available" do
      before do
        create(:room_inventory, room_type: room_type, date: Date.today,
               quantity: 1, status: "open", available_room_numbers: [ "101" ])
      end

      it "checks in the booking and redirects to success" do
        post concierge_submit_check_in_path(hotel.slug)
        expect(response).to redirect_to(concierge_check_in_success_path(hotel.slug))
        expect(booking.reload.status).to eq("checked_in")
      end
    end

    context "no room available" do
      it "re-renders check_in_now with 422" do
        post concierge_submit_check_in_path(hotel.slug)
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("front desk")
      end
    end

    context "wrong date" do
      before { booking.update!(check_in: Date.tomorrow, check_out: Date.tomorrow + 1) }

      it "re-renders with wrong date message" do
        post concierge_submit_check_in_path(hotel.slug)
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include(Date.tomorrow.strftime("%d %b %Y"))
      end
    end
  end

  describe "late flow — past check-in time, pre-checkin not done" do
    let(:kl_zone) { Time.find_zone("Kuala Lumpur") }
    let(:policy) { hotel.build_property_policy(check_in_time: "15:00", check_out_time: "12:00", currency: "MYR", usd_rate: 4.5) }

    before do
      policy.save!
      travel_to kl_zone.parse("#{Date.today} 16:00") do
        post concierge_check_in_lookup_path(hotel.slug),
             params: { confirmation_token: booking.confirmation_token }
      end
    end

    it "redirects to check_in_now when past check-in time and no pre-checkin" do
      travel_to kl_zone.parse("#{Date.today} 16:00") do
        post concierge_check_in_lookup_path(hotel.slug),
             params: { confirmation_token: booking.confirmation_token }
        expect(response).to redirect_to(concierge_check_in_now_path(hotel.slug))
      end
    end

    it "check_in_now renders inline registration form" do
      travel_to kl_zone.parse("#{Date.today} 16:00") do
        post concierge_check_in_lookup_path(hotel.slug),
             params: { confirmation_token: booking.confirmation_token }
      end
      get concierge_check_in_now_path(hotel.slug)
      expect(response.body).to include("Guest Registration")
      expect(response.body).to include("guest_home_address")
    end

    it "submit_check_in saves guest fields and checks in" do
      travel_to kl_zone.parse("#{Date.today} 16:00") do
        post concierge_check_in_lookup_path(hotel.slug),
             params: { confirmation_token: booking.confirmation_token }
        create(:room_inventory, room_type: room_type, date: Date.today,
               quantity: 1, status: "open", available_room_numbers: [ "101" ])

        post concierge_submit_check_in_path(hotel.slug), params: {
          booking: {
            guest_name: "Ahmad Zulkifli",
            guest_email: "ahmad@example.com",
            guest_phone: "+60123456789",
            guest_country: "Malaysia",
            guest_document_type: "ic",
            guest_government_id: "900101011234",
            guest_home_address: "No. 12, Jalan Ampang, 50450 KL"
          }
        }
      end

      expect(response).to redirect_to(concierge_check_in_success_path(hotel.slug))
      expect(booking.reload.status).to eq("checked_in")
      expect(booking.reload.guest_home_address).to eq("No. 12, Jalan Ampang, 50450 KL")
    end

    it "submit_check_in re-renders with error when guest fields missing" do
      travel_to kl_zone.parse("#{Date.today} 16:00") do
        post concierge_check_in_lookup_path(hotel.slug),
             params: { confirmation_token: booking.confirmation_token }
      end

      post concierge_submit_check_in_path(hotel.slug), params: {
        booking: {
          guest_name: "Ahmad Zulkifli",
          guest_email: "",
          guest_phone: "+60123456789",
          guest_country: "Malaysia",
          guest_document_type: "ic",
          guest_government_id: "900101011234",
          guest_home_address: "No. 12, Jalan Ampang"
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
