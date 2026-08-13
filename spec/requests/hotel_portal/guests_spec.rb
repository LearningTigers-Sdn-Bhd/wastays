# frozen_string_literal: true

require "rails_helper"
require "cgi"

RSpec.describe "HotelPortal::Guests", type: :request do
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, status: "live", plan: plan) }
  let(:user) { create(:user) }

  before do
    role = create(:role, account: hotel.account)
    role.permissions << (Permission.find_by(slug: 'view_guest_records') || create(:permission, slug: 'view_guest_records'))
    role.permissions << (Permission.find_by(slug: 'manage_bookings') || create(:permission, slug: 'manage_bookings'))
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: "unified_guest_profile"), enabled: true)
    sign_in_as(user)
  end

  describe "GET /index" do
    it "renders guests in a table layout" do
      guest = Guest.create!(
        name: "Ravi Menon",
        email: "ravi@example.com",
        phone: "+60123456789",
        government_id: "A1234567",
        country: "India",
        gender: "male",
        document_type: "passport",
        date_of_birth: Date.new(1985, 1, 2)
      )

      booking = create(
        :booking,
        hotel: hotel,
        status: "completed",
        guest_name: guest.name,
        guest_email: guest.email,
        guest_phone: guest.phone,
        check_out: Date.new(2026, 4, 2),
        total_amount: 720.0,
        currency: "MYR"
      )
      booking.update_column(:checked_out_at, Time.zone.parse("2026-04-02 14:30:00"))
      create(:booking_guest, booking: booking, guest: guest, is_primary: true)

      get hotel_guests_path(hotel)

      expect(response).to have_http_status(:success)
      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).to include("<table")
      expect(body_text).to include("Ravi Menon")
      expect(body_text).to include(hotel.name[0...10])
      expect(body_text).to include("Guest Records")
      expect(body_text).to include("Country")
      expect(body_text).to include("Stays")
      expect(body_text).to include("Last Stayed")
      expect(body_text).to include("Lifetime Value")
      expect(body_text).to include("02:30 PM")
      expect(body_text).to include("View Timeline")
    end

    it "only counts checked in and completed bookings in lifetime value" do
      guest = Guest.create!(
        name: "Ravi Menon",
        email: "ravi@example.com",
        phone: "+60123456789",
        government_id: "A1234567",
        country: "India",
        gender: "male",
        document_type: "passport",
        date_of_birth: Date.new(1985, 1, 2)
      )

      confirmed_booking = create(:booking, hotel: hotel, status: "confirmed", guest_name: guest.name, guest_email: guest.email, guest_phone: guest.phone, currency: "MYR", total_amount: 500.0)
      checked_in_booking = create(:booking, hotel: hotel, status: "checked_in", guest_name: guest.name, guest_email: guest.email, guest_phone: guest.phone, currency: "MYR", total_amount: 300.0)
      cancelled_booking = create(:booking, hotel: hotel, status: "cancelled", guest_name: guest.name, guest_email: guest.email, guest_phone: guest.phone, currency: "MYR", total_amount: 200.0)
      create(:booking_guest, booking: confirmed_booking, guest: guest, is_primary: true)
      create(:booking_guest, booking: checked_in_booking, guest: guest)
      create(:booking_guest, booking: cancelled_booking, guest: guest)

      get hotel_guests_path(hotel)

      expect(response).to have_http_status(:success)
      expect(CGI.unescapeHTML(response.body)).to include("MYR 300.00")
      expect(CGI.unescapeHTML(response.body)).not_to include("MYR 500.00")
      expect(CGI.unescapeHTML(response.body)).not_to include("MYR 200.00")
    end

    it "filters guests by search query and country" do
      ravi = Guest.create!(
        name: "Ravi Menon",
        email: "ravi@example.com",
        phone: "+60123456789",
        government_id: "A1234567",
        country: "India",
        gender: "male",
        document_type: "passport",
        date_of_birth: Date.new(1985, 1, 2)
      )
      aisha = Guest.create!(
        name: "Aisha Tan",
        email: "aisha@example.com",
        phone: "+60199887766",
        government_id: "900101015555",
        country: "Malaysia",
        gender: "female",
        document_type: "ic"
      )

      ravi_booking = create(:booking, hotel: hotel, status: "completed", guest_name: ravi.name, guest_email: ravi.email, guest_phone: ravi.phone)
      aisha_booking = create(:booking, hotel: hotel, status: "completed", guest_name: aisha.name, guest_email: aisha.email, guest_phone: aisha.phone)
      create(:booking_guest, booking: ravi_booking, guest: ravi, is_primary: true)
      create(:booking_guest, booking: aisha_booking, guest: aisha, is_primary: true)

      get hotel_guests_path(hotel), params: { query: "ravi", country: "India" }

      expect(response).to have_http_status(:success)
      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).to include("Guest Directory")
      expect(body_text).to include("Guest Records")
      expect(body_text).to include("All Countries")
      expect(body_text).to include("Ravi Menon")
      expect(body_text).not_to include("Aisha Tan")
    end

    it "filters guests by status tags" do
      ravi = Guest.create!(
        name: "Ravi Vip",
        email: "vip@example.com",
        phone: "+60123456789",
        government_id: "A1234567",
        country: "India",
        gender: "male",
        document_type: "passport",
        date_of_birth: Date.new(1985, 1, 2),
        vip: true
      )
      aisha = Guest.create!(
        name: "Aisha Banned",
        email: "banned@example.com",
        phone: "+60199887766",
        government_id: "900101015555",
        country: "Malaysia",
        gender: "female",
        document_type: "ic",
        blacklisted: true
      )

      ravi_booking = create(:booking, hotel: hotel, status: "completed", guest_name: ravi.name, guest_email: ravi.email, guest_phone: ravi.phone)
      aisha_booking = create(:booking, hotel: hotel, status: "completed", guest_name: aisha.name, guest_email: aisha.email, guest_phone: aisha.phone)
      create(:booking_guest, booking: ravi_booking, guest: ravi, is_primary: true)
      create(:booking_guest, booking: aisha_booking, guest: aisha, is_primary: true)

      get hotel_guests_path(hotel), params: { tag: "vip" }
      expect(response).to have_http_status(:success)
      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).to include("Ravi Vip")
      expect(body_text).not_to include("Aisha Banned")

      get hotel_guests_path(hotel), params: { tag: "banned" }
      expect(response).to have_http_status(:success)
      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).to include("Aisha Banned")
      expect(body_text).not_to include("Ravi Vip")

      # 3. Repeat filter
      ravi_booking2 = create(:booking, hotel: hotel, status: "completed")
      create(:booking_guest, booking: ravi_booking2, guest: ravi)

      get hotel_guests_path(hotel), params: { tag: "repeat" }
      expect(response).to have_http_status(:success)
      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).to include("Ravi Vip")
      expect(body_text).not_to include("Aisha Banned")
    end
  end

  describe "GET /search" do
    it "returns guest identity fields for booking autocomplete" do
      guest = Guest.create!(
        name: "Nur Aina",
        email: "aina@example.com",
        phone: "+60121112222",
        government_id: "P123456",
        country: "Malaysia",
        gender: "female",
        document_type: "passport",
        date_of_birth: Date.new(1994, 6, 7),
        created_by_hotel: hotel
      )

      get search_hotel_guests_path(hotel), params: { q: "Nur" }

      expect(response).to have_http_status(:success)
      result = JSON.parse(response.body).fetch("results").first
      expect(result).to include(
        "value" => guest.id,
        "label" => "Nur Aina",
        "description" => "aina@example.com · +60121112222"
      )
      expect(result.fetch("data")).to include(
        "name" => "Nur Aina",
        "email" => "aina@example.com",
        "phone" => "+60121112222",
        "country" => "Malaysia",
        "gender" => "female",
        "date_of_birth" => "1994-06-07",
        "blacklisted" => false
      )
    end
  end

  describe "POST /create" do
    it "permits date of birth when creating a guest" do
      post hotel_guests_path(hotel), params: {
        guest: {
          name: "Create Guest",
          email: "create@example.com",
          country: "Malaysia",
          document_type: "passport",
          date_of_birth: "1990-08-09"
        }
      }

      expect(response).to redirect_to(hotel_guest_path(hotel, Guest.last))
      expect(Guest.last.date_of_birth).to eq(Date.new(1990, 8, 9))
    end
  end

  describe "PATCH /update" do
    it "permits date of birth when updating a guest" do
      guest = create(
        :guest,
        created_by_hotel: hotel,
        country: "Malaysia",
        document_type: "passport",
        date_of_birth: Date.new(1988, 1, 1)
      )

      patch hotel_guest_path(hotel, guest), params: {
        guest: {
          date_of_birth: "1992-03-04"
        }
      }

      expect(response).to redirect_to(hotel_guest_path(hotel, guest))
      expect(guest.reload.date_of_birth).to eq(Date.new(1992, 3, 4))
    end
  end

  describe "GET /show" do
    it "renders the guest timeline without grouped query errors" do
      guest = Guest.create!(
        name: "Ravi Menon",
        email: "ravi@example.com",
        phone: "+60123456789",
        government_id: "A1234567",
        country: "India",
        gender: "male",
        document_type: "passport",
        date_of_birth: Date.new(1985, 1, 2)
      )

      myr_booking = create(
        :booking,
        hotel: hotel,
        status: "completed",
        guest_name: guest.name,
        guest_email: guest.email,
        guest_phone: guest.phone,
        currency: "MYR",
        total_amount: 720.0
      )
      usd_booking = create(
        :booking,
        hotel: hotel,
        status: "completed",
        guest_name: guest.name,
        guest_email: guest.email,
        guest_phone: guest.phone,
        currency: "USD",
        total_amount: 100.0
      )
      create(:booking_guest, booking: myr_booking, guest: guest, is_primary: true)
      create(:booking_guest, booking: usd_booking, guest: guest)

      get hotel_guest_path(hotel, guest)
      body_text = CGI.unescapeHTML(response.body)

      expect(response).to have_http_status(:success)
      expect(body_text).to include(hotel.name[0...10])
      expect(body_text).to include("Guest Records")
      expect(body_text).to include("Ravi Menon")
      expect(body_text).to include("Currency Totals")
      expect(body_text).to include("Booking History")
      expect(body_text).to include("Confirmation")
      expect(body_text).to include("Pre-Check-In")
      expect(body_text).to include("MYR")
      expect(body_text).to include("USD")
      expect(body_text.downcase).to include("india")
    end

    it "only totals checked in and completed bookings" do
      guest = Guest.create!(
        name: "Ravi Menon",
        email: "ravi@example.com",
        phone: "+60123456789",
        government_id: "A1234567",
        country: "India",
        gender: "male",
        document_type: "passport",
        date_of_birth: Date.new(1985, 1, 2)
      )

      confirmed_booking = create(:booking, hotel: hotel, status: "confirmed", guest_name: guest.name, guest_email: guest.email, guest_phone: guest.phone, currency: "MYR", total_amount: 500.0)
      checked_in_booking = create(:booking, hotel: hotel, status: "checked_in", guest_name: guest.name, guest_email: guest.email, guest_phone: guest.phone, currency: "MYR", total_amount: 300.0)
      completed_booking = create(:booking, hotel: hotel, status: "completed", guest_name: guest.name, guest_email: guest.email, guest_phone: guest.phone, currency: "USD", total_amount: 100.0)
      cancelled_booking = create(:booking, hotel: hotel, status: "cancelled", guest_name: guest.name, guest_email: guest.email, guest_phone: guest.phone, currency: "MYR", total_amount: 200.0)
      create(:booking_guest, booking: confirmed_booking, guest: guest, is_primary: true)
      create(:booking_guest, booking: checked_in_booking, guest: guest)
      create(:booking_guest, booking: completed_booking, guest: guest)
      create(:booking_guest, booking: cancelled_booking, guest: guest)

      get hotel_guest_path(hotel, guest)
      body_text = CGI.unescapeHTML(response.body)

      expect(response).to have_http_status(:success)
      expect(body_text).to include("RM 300.00")
      expect(body_text).to include("USD 100.00")
    end

    it "keeps confirmed and cancelled bookings visible in the history" do
      guest = Guest.create!(
        name: "Ravi Menon",
        email: "ravi@example.com",
        phone: "+60123456789",
        government_id: "A1234567",
        country: "India",
        gender: "male",
        document_type: "passport",
        date_of_birth: Date.new(1985, 1, 2)
      )

      confirmed_booking = create(:booking, hotel: hotel, status: "confirmed", guest_name: guest.name, guest_email: guest.email, guest_phone: guest.phone, currency: "MYR", total_amount: 500.0)
      cancelled_booking = create(:booking, hotel: hotel, status: "cancelled", guest_name: guest.name, guest_email: guest.email, guest_phone: guest.phone, currency: "MYR", total_amount: 200.0)
      create(:booking_guest, booking: confirmed_booking, guest: guest, is_primary: true)
      create(:booking_guest, booking: cancelled_booking, guest: guest)

      get hotel_guest_path(hotel, guest)
      body_text = CGI.unescapeHTML(response.body)

      expect(response).to have_http_status(:success)
      expect(body_text).to include(confirmed_booking.confirmation_token)
      expect(body_text).to include(cancelled_booking.confirmation_token)
    end
  end

  describe "DELETE /bulk_destroy" do
    let(:role_with_delete) do
      role = create(:role, account: hotel.account)
      role.permissions << (Permission.find_by(slug: 'view_guest_records') || create(:permission, slug: 'view_guest_records'))
      role.permissions << (Permission.find_by(slug: 'delete_guest_record') || create(:permission, slug: 'delete_guest_record'))
      role
    end

    let(:guest1) { Guest.create!(name: "Guest One", email: "one@example.com", phone: "+60123456781", government_id: "A1234561", country: "Malaysia", gender: "male", document_type: "passport", date_of_birth: Date.new(1980, 1, 1), created_by_hotel: hotel) }
    let(:guest2) { Guest.create!(name: "Guest Two", email: "two@example.com", phone: "+60123456782", government_id: "A1234562", country: "Malaysia", gender: "female", document_type: "passport", date_of_birth: Date.new(1981, 2, 2), created_by_hotel: hotel) }

    context "when user has delete permission" do
      before do
        UserHotelAccess.find_by(user: user, hotel: hotel).update!(role: role_with_delete)
      end

      it "soft deletes selected guests" do
        delete bulk_destroy_hotel_guests_path(hotel), params: { guest_ids: [ guest1.id, guest2.id ].to_json }

        expect(response).to redirect_to(hotel_guests_path(hotel))
        expect(flash[:notice]).to eq("Selected guest records removed successfully.")
        expect(guest1.reload.discarded?).to be true
        expect(guest2.reload.discarded?).to be true
      end
    end

    context "when user does not have delete permission" do
      it "redirects to root path with not authorized alert" do
        delete bulk_destroy_hotel_guests_path(hotel), params: { guest_ids: [ guest1.id, guest2.id ].to_json }

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("not authorized")
      end
    end
  end
end
