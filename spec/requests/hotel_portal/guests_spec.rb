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
      expect(body_text).to include("Contact")
      expect(body_text).to include("Stays")
      expect(body_text).to include("Last stayed")
      expect(body_text).to include("Lifetime value")
      expect(body_text).to include("02:30 PM")
      expect(body_text).to include("View record")
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
            expect(body_text).to include("Guest Records")
      expect(body_text).to include("All countries")
      expect(body_text).to include("Ravi Menon")
      expect(body_text).not_to include("Aisha Tan")
    end

    it "renders a tab per status with its own count" do
      vip = Guest.create!(name: "Vip Guest", email: "vip@example.com", vip: true, country: "Malaysia")
      plain = Guest.create!(name: "Plain Guest", email: "plain@example.com", country: "Malaysia")
      [ vip, plain ].each do |guest|
        booking = create(:booking, hotel: hotel, status: "completed", guest_name: guest.name, guest_email: guest.email)
        create(:booking_guest, booking: booking, guest: guest, is_primary: true)
      end

      get hotel_guests_path(hotel), params: { tag: "vip" }

      expect(response).to have_http_status(:success)
      strip = response.body[/<nav[^>]*guest-tag-tabs.*?<\/nav>/m] || response.body
      expect(strip).to include("Blacklisted")
      expect(strip).to include("Repeat")
      expect(strip).to match(/aria-current="page"[^>]*>(?:(?!<\/a>).)*VIP/m)
    end

    it "treats the legacy banned tag as the blacklisted tab" do
      get hotel_guests_path(hotel), params: { tag: "banned" }

      expect(response).to have_http_status(:success)
      expect(response.body).to match(/aria-current="page"[^>]*>(?:(?!<\/a>).)*Blacklisted/m)
    end

    it "offers every row action in one menu" do
      guest = Guest.create!(name: "Ravi Menon", email: "ravi@example.com", country: "India",
                            document_type: "passport", government_id: "A1234567",
                            date_of_birth: Date.new(1985, 1, 2))
      booking = create(:booking, hotel: hotel, status: "completed", guest_name: guest.name, guest_email: guest.email)
      create(:booking_guest, booking: booking, guest: guest, is_primary: true)

      get hotel_guests_path(hotel)

      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).to include("Actions for Ravi Menon")
      expect(body_text).to include("View record")
      expect(body_text).to include("Edit profile")
      expect(body_text).to include("Mark as VIP")
      expect(body_text).to include("Blacklist guest")
      expect(body_text).to include(vip_hotel_guest_path(hotel, guest))
    end

    it "renders the design system checkbox for selection" do
      role = user.user_hotel_accesses.first.role
      role.permissions << (Permission.find_by(slug: "delete_guest_record") || create(:permission, slug: "delete_guest_record"))

      guest = Guest.create!(name: "Ravi Menon", email: "ravi@example.com", country: "Malaysia")
      booking = create(:booking, hotel: hotel, status: "completed", guest_name: guest.name, guest_email: guest.email)
      create(:booking_guest, booking: booking, guest: guest, is_primary: true)

      get hotel_guests_path(hotel)

      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).to include("panel-checkbox")
      expect(body_text).to include("Select Ravi Menon")
      expect(body_text).to include("Select every guest on this page")
      expect(body_text).not_to include("Select All Guests")
    end

    it "reads the repeat flag for the whole page in one query" do
      3.times do |index|
        guest = Guest.create!(name: "Guest #{index}", email: "guest#{index}@example.com", country: "Malaysia")
        2.times do
          booking = create(:booking, hotel: hotel, status: "completed", guest_name: guest.name, guest_email: guest.email)
          create(:booking_guest, booking: booking, guest: guest, is_primary: true)
        end
      end

      queries = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        queries << payload[:sql] if payload[:sql].include?("booking_guests") && payload[:sql].include?("HAVING")
      end

      get hotel_guests_path(hotel)

      ActiveSupport::Notifications.unsubscribe(subscriber)

      expect(response).to have_http_status(:success)
      expect(CGI.unescapeHTML(response.body)).to include("Repeat")
      # One for the tab counts, one for the page's rows — not one per guest.
      expect(queries.size).to be <= 2
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

      # The directory sends "blacklisted"; it must match the same records.
      get hotel_guests_path(hotel), params: { tag: "blacklisted" }
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
        home_address: "No. 12, Jalan Ampang",
        city: "Kuala Lumpur",
        state_code: "14",
        postal_code: "50450",
        address_country: "Malaysia",
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
        "home_address" => "No. 12, Jalan Ampang",
        "city" => "Kuala Lumpur",
        "state_code" => "14",
        "postal_code" => "50450",
        "address_country" => "Malaysia",
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

      expect(response).to redirect_to(details_hotel_guest_path(hotel, Guest.last))
      expect(Guest.last.date_of_birth).to eq(Date.new(1990, 8, 9))
    end

    it "permits an optional home address when creating a guest" do
      post hotel_guests_path(hotel), params: {
        guest: {
          name: "Create Guest",
          email: "create2@example.com",
          country: "Malaysia",
          home_address: "No. 12, Jalan Ampang"
        }
      }

      expect(response).to redirect_to(details_hotel_guest_path(hotel, Guest.last))
      expect(Guest.last.home_address).to eq("No. 12, Jalan Ampang")
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

      expect(response).to redirect_to(details_hotel_guest_path(hotel, guest))
      expect(guest.reload.date_of_birth).to eq(Date.new(1992, 3, 4))
    end
  end

  describe "GET /details and /booking_history" do
    it "renders the guest timeline without grouped query errors" do
      guest = Guest.create!(
        name: "Ravi Menon",
        email: "ravi@example.com",
        phone: "+60123456789",
        government_id: "A1234567",
        country: "India",
        gender: "male",
        document_type: "passport",
        date_of_birth: Date.new(1985, 1, 2),
        home_address: "No. 12, Jalan Ampang"
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

      get details_hotel_guest_path(hotel, guest)
      body_text = CGI.unescapeHTML(response.body)

      expect(response).to have_http_status(:success)
      expect(body_text).to include(hotel.name[0...10])
      expect(body_text).to include("Guest Records")
      expect(body_text).to include("Ravi Menon")
      expect(body_text).to include("Guest identity")
      expect(body_text).to include("Guest address")
      expect(body_text).to include("Stay summary")
      expect(body_text.downcase).to include("india")
      expect(body_text).to include("No. 12, Jalan Ampang")

      get booking_history_hotel_guest_path(hotel, guest)
      body_text = CGI.unescapeHTML(response.body)

      expect(response).to have_http_status(:success)
      expect(body_text).to include("Lifetime value")
      expect(body_text).to include("<tfoot>")
      expect(body_text).to include("Booking History")
      expect(body_text).to include("Confirmation")
      expect(body_text).to include("Pre-check-in")
      expect(body_text).to include("MYR")
      expect(body_text).to include("USD")
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

      get booking_history_hotel_guest_path(hotel, guest)
      body_text = CGI.unescapeHTML(response.body)

      expect(response).to have_http_status(:success)
      expect(body_text).to include("MYR 300.00")
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

      get booking_history_hotel_guest_path(hotel, guest)
      body_text = CGI.unescapeHTML(response.body)

      expect(response).to have_http_status(:success)
      expect(body_text).to include(confirmed_booking.confirmation_token)
      expect(body_text).to include(cancelled_booking.confirmation_token)
    end
  end

  describe "GET /show" do
    it "sends the reader to the details tab" do
      guest = create(:guest, created_by_hotel: hotel)

      get hotel_guest_path(hotel, guest)

      expect(response).to redirect_to(details_hotel_guest_path(hotel, guest))
    end
  end

  describe "tab query cost" do
    let(:guest) { create(:guest, created_by_hotel: hotel) }

    before do
      booking = create(:booking, hotel: hotel, status: "completed", currency: "MYR", total_amount: 300.0)
      create(:booking_guest, booking: booking, guest: guest, is_primary: true)
    end

    it "does not load the booking rows on the details tab" do
      expect_any_instance_of(Guests::GuestBookingsQuery).not_to receive(:bookings)
      expect_any_instance_of(Guests::GuestBookingsQuery).not_to receive(:currency_totals)

      get details_hotel_guest_path(hotel, guest)

      expect(response).to have_http_status(:success)
    end

    it "loads the booking rows on the booking history tab" do
      get booking_history_hotel_guest_path(hotel, guest)

      expect(response).to have_http_status(:success)
      expect(CGI.unescapeHTML(response.body)).to include("MYR 300.00")
    end
  end

  describe "record page shell" do
    let(:guest) { create(:guest, created_by_hotel: hotel, name: "Ravi Menon") }

    it "carries the header, both tabs and the actions menu" do
      get details_hotel_guest_path(hotel, guest)

      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).to include("Ravi Menon")
      expect(body_text).to include("guest-record-tabs")
      expect(body_text).to include("Booking History")
      expect(body_text).to include("guest-record-actions")
      expect(body_text).to include("Mark as VIP")
      expect(body_text).to include("Blacklist guest")
    end

    it "offers the reverse actions once the guest is marked" do
      Guests::SetVip.new(guests: guest, hotel: hotel, vip: true).call
      Guests::SetBlacklist.new(guests: guest, hotel: hotel, blacklisted: true, actor: user, reason: "Damage").call

      get details_hotel_guest_path(hotel, guest)

      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).to include("Remove VIP")
      expect(body_text).to include("Remove blacklist")
      expect(body_text).not_to include("Mark as VIP")
    end

    # The badges are the at-a-glance marker beside the name. The Stay summary
    # section carries the same state with its detail; both are wanted.
    it "shows the status badges in the header and again in the stay summary" do
      Guests::SetVip.new(guests: guest, hotel: hotel, vip: true).call
      Guests::SetBlacklist.new(guests: guest, hotel: hotel, blacklisted: true, actor: user, reason: "Damaged the room").call

      get details_hotel_guest_path(hotel, guest)

      body_text = CGI.unescapeHTML(response.body)
      header = body_text[/<header[^>]*data-testid="guest-record-header"[\s\S]*?<\/header>/]
      expect(header).to include("VIP")
      expect(header).to include("Blacklisted")

      expect(body_text).to include("Status at #{hotel.name}")
      expect(body_text).to include("Blacklist reason")
      expect(body_text).to include("Damaged the room")
    end

    it "returns the tab strip and body, without the page shell, to a frame request" do
      get details_hotel_guest_path(hotel, guest), headers: { "Turbo-Frame" => "guest_record" }

      expect(response).to have_http_status(:success)
      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).to include("guest_record")
      expect(body_text).to include("Guest identity")
      expect(body_text).not_to include("<!DOCTYPE html>")
      expect(body_text).not_to include("guest-record-actions")
    end

    # The tab strip has to travel inside the frame. Left outside it, the
    # highlight stays on whichever tab the reader arrived on.
    it "marks the tab it returns as the current one" do
      get details_hotel_guest_path(hotel, guest), headers: { "Turbo-Frame" => "guest_record" }
      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).to match(/id="guest-record-tabs-tab-details"[^>]*aria-current="page"/)
      expect(body_text).not_to match(/id="guest-record-tabs-tab-booking_history"[^>]*aria-current="page"/)

      get booking_history_hotel_guest_path(hotel, guest), headers: { "Turbo-Frame" => "guest_record" }
      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).to match(/id="guest-record-tabs-tab-booking_history"[^>]*aria-current="page"/)
      expect(body_text).not_to match(/id="guest-record-tabs-tab-details"[^>]*aria-current="page"/)
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

  describe "PATCH /vip and /unvip" do
    let(:guest) { create(:guest, created_by_hotel: hotel) }

    it "marks the guest record as VIP" do
      patch vip_hotel_guest_path(hotel, guest)

      expect(response).to redirect_to(details_hotel_guest_path(hotel, guest))
      expect(flash[:notice]).to include("marked as VIP")
      expect(guest.reload.vip).to be true
    end

    it "removes VIP from the guest record" do
      guest.update!(vip: true)

      patch unvip_hotel_guest_path(hotel, guest)

      expect(flash[:notice]).to include("VIP removed")
      expect(guest.reload.vip).to be false
    end
  end

  describe "PATCH /blacklist and /unblacklist" do
    let(:guest) { create(:guest, created_by_hotel: hotel) }

    it "blacklists the guest record with a reason" do
      patch blacklist_hotel_guest_path(hotel, guest), params: { blacklist_reason: "Damaged the room" }

      expect(response).to redirect_to(details_hotel_guest_path(hotel, guest))
      expect(flash[:notice]).to include("blacklisted")
      guest.reload
      expect(guest.blacklisted_at?(hotel)).to be true
      expect(guest.blacklist_detail(hotel)["reason"]).to eq("Damaged the room")
      expect(guest.blacklist_detail(hotel)["blacklisted_by_id"]).to eq(user.id)
    end

    it "refuses to blacklist without a reason" do
      patch blacklist_hotel_guest_path(hotel, guest), params: { blacklist_reason: "" }

      expect(flash[:alert]).to include("provide a reason")
      expect(guest.reload.blacklisted_at?(hotel)).to be false
    end

    it "clears the blacklist" do
      Guests::SetBlacklist.new(guests: guest, hotel: hotel, blacklisted: true, actor: user, reason: "Damage").call

      patch unblacklist_hotel_guest_path(hotel, guest)

      expect(flash[:notice]).to include("Blacklist removed")
      expect(guest.reload.blacklisted_at?(hotel)).to be false
    end
  end
end
