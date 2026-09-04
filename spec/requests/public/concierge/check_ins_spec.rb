require "rails_helper"

RSpec.describe "Public::Concierge::CheckIns", type: :request do
  let(:feature_group) { create(:feature_group) }
  let(:ai_concierge_page_feature) { create(:feature, feature_group: feature_group, slug: "ai_concierge_page") }
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, status: "live", concierge_enabled: true, plan: plan) }

  before do
    create(:plan_feature, plan: plan, feature: ai_concierge_page_feature, enabled: true)
  end
  let(:room_type) do
    create(:room_type, hotel: hotel, room_number_mode: "custom", quantity: 1, room_numbers: [ "101" ])
  end
  let(:booking) do
    b = create(:booking, hotel: hotel, guest_name: "Ahmad Zulkifli", status: "confirmed",
               check_in: Date.today, check_out: Date.today + 1)
    b.booking_rooms.create!(room_type: room_type, subtotal: 200,
                             room_type_snapshot: { "name" => room_type.name })
    b
  end

  before do
    Rails.cache.clear
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current)
  end

  describe "GET /concierge/:hotel_slug/check-in" do
    it "renders the chooser page" do
      get concierge_check_in_path(hotel)
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

      it "redirects to check-in now page" do
        with_frozen_time kl_zone.parse("#{Date.today} 09:00") do
          post concierge_check_in_lookup_path(hotel),
               params: { confirmation_token: booking.confirmation_token }
          expect(response).to redirect_to(concierge_check_in_now_path(hotel))
        end
      end
    end

    context "pre-checkin already completed" do
      before do
        booking.create_pre_checkin!(status: "completed", document_status: "verified",
                                    signature_status: "signed", completed_at: Time.current)
      end

      it "redirects to check-in now page" do
        post concierge_check_in_lookup_path(hotel),
             params: { confirmation_token: booking.confirmation_token }
        expect(response).to redirect_to(concierge_check_in_now_path(hotel))
      end
    end

    it "re-renders with error on unknown token" do
      post concierge_check_in_lookup_path(hotel),
           params: { confirmation_token: "WS-XXXXXXXX" }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /concierge/:hotel_slug/check-in/now" do
    before do
      booking.create_pre_checkin!(status: "completed", document_status: "verified",
                                  signature_status: "signed", completed_at: Time.current)
      post concierge_check_in_lookup_path(hotel),
           params: { confirmation_token: booking.confirmation_token }
    end

    context "room available", frozen_time: -> { Time.find_zone("Kuala Lumpur").parse("#{Date.today} 15:00") } do
      before do
        create(:room_inventory, room_type: room_type, date: Date.today,
               quantity: 1, status: "open", available_room_numbers: [ "101" ])
      end

      it "checks in the booking and redirects to success" do
        post concierge_submit_check_in_path(hotel)
        expect(response).to redirect_to(concierge_check_in_success_path(hotel))
        expect(booking.reload.status).to eq("checked_in")
        expect(booking.booking_rooms.first.reload.room_number).to eq("101")
        expect(booking.booking_folio).to be_present
        expect(BookingAuditLog.find_by!(auditable: booking, action_type: "check_in").source).to eq("concierge_page")
      end
    end

    context "no room available" do
      before do
        create(:room_inventory, room_type: room_type, date: Date.today,
               quantity: 0, status: "closed", available_room_numbers: [])
      end

      it "re-renders check_in_now with 422" do
        post concierge_submit_check_in_path(hotel)
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("front desk")
      end
    end

    context "closed check-in business date" do
      before do
        hotel.current_business_date_record.update!(status: "closed")
        create(:room_inventory, room_type: room_type, date: Date.today,
               quantity: 1, status: "open", available_room_numbers: [ "101" ])
      end

      it "shows guest-facing front desk guidance" do
        post concierge_submit_check_in_path(hotel)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include(
          "We&#39;re unable to complete self check-in for this stay. Please visit the front desk for assistance."
        )
        expect(response.body).not_to include("Reason required for backdated check-in on closed date")
      end
    end

    context "wrong date", frozen_time: Time.zone.local(2026, 6, 10, 3) do
      before { booking.update!(check_in: Date.tomorrow, check_out: Date.tomorrow + 1) }

      it "re-renders with wrong date message" do
        post concierge_submit_check_in_path(hotel)
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include(Date.tomorrow.strftime("%d %b %Y"))
      end
    end

    context "updated check-in policy after booking creation with default",
            frozen_time: -> { Time.find_zone("Kuala Lumpur").parse("#{Date.today} 14:25").utc } do
      let(:kl_zone) { Time.find_zone("Kuala Lumpur") }

      before do
        hotel.create_property_policy!(check_in_time: "14:00", check_out_time: "12:00", currency: "MYR") unless hotel.property_policy
        hotel.property_policy.update!(check_in_time: "14:00")
        booking.update_columns(check_in: kl_zone.parse("#{Date.today} 15:00").utc)
        create(:room_inventory, room_type: room_type, date: Date.today,
               quantity: 1, status: "open", available_room_numbers: [ "101" ])
      end

      it "checks in the booking at 14:25 successfully because of the 14:00 policy" do
        post concierge_submit_check_in_path(hotel)
        expect(response).to redirect_to(concierge_check_in_success_path(hotel))
        expect(booking.reload.status).to eq("checked_in")
      end
    end

    context "with geolocation check enabled",
            frozen_time: -> { Time.find_zone("Kuala Lumpur").parse("#{Date.today} 15:00") } do
      before do
        hotel.update!(google_map_link: "https://www.google.com/maps/place/Sample+Hotel/@5.9771228,116.0622732,15z")
        create(:room_inventory, room_type: room_type, date: Date.today,
               quantity: 1, status: "open", available_room_numbers: [ "101" ])
      end

      it "fails with :missing_location when no coordinates are submitted" do
        post concierge_submit_check_in_path(hotel)
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Location access is required")
      end

      it "fails with :too_far_away when coordinates are outside radius" do
        post concierge_submit_check_in_path(hotel), params: { latitude: 3.1390, longitude: 101.6869 }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("too far from the hotel")
      end

      it "succeeds when coordinates are within the radius" do
        post concierge_submit_check_in_path(hotel), params: { latitude: 5.9772, longitude: 116.0623 }
        expect(response).to redirect_to(concierge_check_in_success_path(hotel))
        expect(booking.reload.status).to eq("checked_in")
      end
    end
  end

  describe "late flow — past check-in time, pre-checkin not done",
           frozen_time: -> { Time.find_zone("Kuala Lumpur").parse("#{Date.today} 16:00").utc } do
    let(:kl_zone) { Time.find_zone("Kuala Lumpur") }
    let(:policy) { hotel.build_property_policy(check_in_time: "15:00", check_out_time: "12:00", currency: "MYR", usd_rate: 4.5) }

    before do
      policy.save!
      post concierge_check_in_lookup_path(hotel),
           params: { confirmation_token: booking.confirmation_token }
    end

    it "redirects to check_in_now when past check-in time and no pre-checkin" do
      expect(response).to redirect_to(concierge_check_in_now_path(hotel))
    end

    it "check_in_now renders inline registration form" do
      get concierge_check_in_now_path(hotel)
      expect(response.body).to include("Guest Registration")
      expect(response.body).to include("guest_home_address")
      expect(response.body).to include("guest_date_of_birth")
    end

    it "submit_check_in saves guest fields and redirects to confirmation, then checks in" do
      create(:room_inventory, room_type: room_type, date: Date.today,
             quantity: 1, status: "open", available_room_numbers: [ "101" ])

      # Step 1: Submit registration details
      post concierge_submit_check_in_path(hotel), params: {
        booking: {
          guest_name: "Ahmad Zulkifli",
          guest_email: "ahmad@example.com",
          guest_phone: "+60123456789",
          guest_country: "Malaysia",
          guest_document_type: "ic",
          guest_government_id: "900101011234",
          guest_home_address: "No. 12, Jalan Ampang",
          guest_city: "Kuala Lumpur",
          guest_state_code: "14",
          guest_postal_code: "50450",
          guest_address_country: "Malaysia"
        }
      }

      expect(response).to redirect_to(concierge_check_in_now_path(hotel))
      expect(booking.reload.pre_checkin_status).to eq("completed")

      # Step 2: Confirm check-in
      post concierge_submit_check_in_path(hotel)
      expect(response).to redirect_to(concierge_check_in_success_path(hotel))
      expect(booking.reload.status).to eq("checked_in")
      expect(booking.reload).to have_attributes(
        guest_home_address: "No. 12, Jalan Ampang",
        guest_city: "Kuala Lumpur",
        guest_state_code: "14",
        guest_postal_code: "50450",
        guest_address_country: "Malaysia"
      )
      expect(BookingAuditLog.where(auditable: booking, action_type: "guest_updated", source: "guest").count).to eq(1)
    end

    it "persists passport guest date of birth during registration" do
      post concierge_submit_check_in_path(hotel), params: {
        booking: {
          guest_name: "Ahmad Zulkifli",
          guest_email: "ahmad@example.com",
          guest_phone: "+60123456789",
          guest_country: "Singapore",
          guest_document_type: "passport",
          guest_government_id: "P1234567",
          guest_date_of_birth: "1994-08-21",
          guest_home_address: "No. 12, Jalan Ampang, 50450 KL",
          guest_city: "Singapore",
          guest_address_country: "Singapore",
          signature: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        }
      }

      expect(response).to redirect_to(concierge_check_in_now_path(hotel))
      expect(booking.reload.primary_guest.date_of_birth).to eq(Date.new(1994, 8, 21))
    end

    it "fails cleanly when passport date of birth is missing" do
      post concierge_submit_check_in_path(hotel), params: {
        booking: {
          guest_name: "Ahmad Zulkifli",
          guest_email: "ahmad@example.com",
          guest_phone: "+60123456789",
          guest_country: "Singapore",
          guest_document_type: "passport",
          guest_government_id: "P1234567",
          guest_date_of_birth: "",
          guest_home_address: "No. 12, Jalan Ampang, 50450 KL",
          guest_city: "Singapore",
          guest_address_country: "Singapore",
          signature: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Date of birth is required for passport guests")
    end

    it "submit_check_in re-renders with error when guest fields missing" do
      allow_any_instance_of(Booking).to receive(:guest_email).and_return(nil)
      post concierge_submit_check_in_path(hotel), params: {
        booking: {
          guest_name: "Ahmad Zulkifli",
          guest_email: "",
          guest_phone: "+60123456789",
          guest_country: "Malaysia",
          guest_document_type: "ic",
          guest_government_id: "900101011234",
          guest_home_address: "No. 12, Jalan Ampang",
          guest_city: "Kuala Lumpur",
          guest_state_code: "14",
          guest_address_country: "Malaysia"
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
