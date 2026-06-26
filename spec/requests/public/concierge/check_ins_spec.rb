require "rails_helper"

RSpec.describe "Public::Concierge::CheckIns", type: :request do
  let(:feature_group) { create(:feature_group) }
  let(:ai_concierge_page_feature) { create(:feature, feature_group: feature_group, slug: "ai_concierge_page") }
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, status: "live", concierge_enabled: true, plan: plan) }

  before do
    create(:plan_feature, plan: plan, feature: ai_concierge_page_feature, enabled: true)
  end
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
    let(:kl_zone) { Time.find_zone("Kuala Lumpur") }

    context "pre-checkin not completed" do
      before do
        hotel.create_property_policy!(check_in_time: "14:00", check_out_time: "12:00")
      end

      it "redirects to pre-checkin form" do
        travel_to kl_zone.parse("#{Date.today} 09:00") do
          post concierge_check_in_lookup_path(hotel.slug),
               params: { confirmation_token: booking.confirmation_token }
          expect(response).to redirect_to(pre_checkin_path(booking.reload.pre_checkin.token))
        end
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
      around { |example| travel_to(Time.zone.local(2026, 6, 10, 3, 0, 0)) { example.run } }
      before { booking.update!(check_in: Date.tomorrow, check_out: Date.tomorrow + 1) }

      it "re-renders with wrong date message" do
        post concierge_submit_check_in_path(hotel.slug)
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include(Date.tomorrow.strftime("%d %b %Y"))
      end
    end

    context "updated check-in policy after booking creation with default" do
      let(:kl_zone) { Time.find_zone("Kuala Lumpur") }

      around do |example|
        travel_to kl_zone.parse("#{Date.today} 14:25").utc do
          example.run
        end
      end

      before do
        hotel.create_property_policy!(check_in_time: "14:00", check_out_time: "12:00", currency: "MYR") unless hotel.property_policy
        hotel.property_policy.update!(check_in_time: "14:00")
        booking.update_columns(check_in: kl_zone.parse("#{Date.today} 15:00").utc)
        create(:room_inventory, room_type: room_type, date: Date.today,
               quantity: 1, status: "open", available_room_numbers: [ "101" ])
      end

      it "checks in the booking at 14:25 successfully because of the 14:00 policy" do
        post concierge_submit_check_in_path(hotel.slug)
        expect(response).to redirect_to(concierge_check_in_success_path(hotel.slug))
        expect(booking.reload.status).to eq("checked_in")
      end
    end

    context "with geolocation check enabled" do
      before do
        hotel.update!(google_map_link: "https://www.google.com/maps/place/Sample+Hotel/@5.9771228,116.0622732,15z")
        create(:room_inventory, room_type: room_type, date: Date.today,
               quantity: 1, status: "open", available_room_numbers: [ "101" ])
      end

      it "fails with :missing_location when no coordinates are submitted" do
        post concierge_submit_check_in_path(hotel.slug)
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Location access is required")
      end

      it "fails with :too_far_away when coordinates are outside radius" do
        post concierge_submit_check_in_path(hotel.slug), params: { latitude: 3.1390, longitude: 101.6869 }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("too far from the hotel")
      end

      it "succeeds when coordinates are within the radius" do
        post concierge_submit_check_in_path(hotel.slug), params: { latitude: 5.9772, longitude: 116.0623 }
        expect(response).to redirect_to(concierge_check_in_success_path(hotel.slug))
        expect(booking.reload.status).to eq("checked_in")
      end
    end
  end

  describe "late flow — past check-in time, pre-checkin not done" do
    let(:kl_zone) { Time.find_zone("Kuala Lumpur") }
    let(:policy) { hotel.build_property_policy(check_in_time: "15:00", check_out_time: "12:00", currency: "MYR", usd_rate: 4.5) }

    around do |example|
      travel_to kl_zone.parse("#{Date.today} 16:00").utc do
        example.run
      end
    end

    before do
      policy.save!
      post concierge_check_in_lookup_path(hotel.slug),
           params: { confirmation_token: booking.confirmation_token }
    end

    it "redirects to check_in_now when past check-in time and no pre-checkin" do
      expect(response).to redirect_to(concierge_check_in_now_path(hotel.slug))
    end

    it "check_in_now renders inline registration form" do
      get concierge_check_in_now_path(hotel.slug)
      expect(response.body).to include("Guest Registration")
      expect(response.body).to include("guest_home_address")
    end

    it "submit_check_in saves guest fields and checks in" do
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

      expect(response).to redirect_to(concierge_check_in_success_path(hotel.slug))
      expect(booking.reload.status).to eq("checked_in")
      expect(booking.reload.guest_home_address).to eq("No. 12, Jalan Ampang, 50450 KL")
      expect(BookingAuditLog.where(auditable: booking, action_type: "guest_updated", source: "guest").count).to eq(1)
    end

    it "submit_check_in re-renders with error when guest fields missing" do
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
