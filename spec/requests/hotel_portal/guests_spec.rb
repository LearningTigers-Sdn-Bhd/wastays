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

    it "renders the bulk bar with the counts each action would change" do
      role = user.user_hotel_accesses.first.role
      role.permissions << (Permission.find_by(slug: "delete_guest_record") || create(:permission, slug: "delete_guest_record"))

      guest = Guest.create!(name: "Ravi Menon", email: "ravi@example.com", country: "Malaysia")
      booking = create(:booking, hotel: hotel, status: "completed", guest_name: guest.name, guest_email: guest.email)
      create(:booking_guest, booking: booking, guest: guest, is_primary: true)

      get hotel_guests_path(hotel)

      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).to include("data-bulk-select-target=\"banner\"")
      expect(body_text).to include("data-bulk-select-noun-value=\"guest\"")
      expect(body_text).to include("data-bulk-kind=\"vip\"")
      expect(body_text).to include("data-bulk-kind=\"unblacklist\"")
      expect(body_text).to include("{skipped} already VIP.")
      expect(body_text).to include("Blacklist selected guests")
      document = Nokogiri::HTML(response.body)
      menu = document.at_css("#guest-bulk-actions-menu")
      expect(menu.css("[role='menuitem']").size).to eq(5)
      expect(document.at_css("#guest-bulk-actions-trigger").text).to include("Actions")
      menu.css("button[type='submit']").each do |button|
        form = document.at_css("form##{button['form']}")
        expect(form).to be_present
        expect(form.at_css("input[data-bulk-select-target='idsInput']")).to be_present
      end
      # Each row states its own status so the confirm can count without asking
      # the server.
      expect(body_text).to include("data-vip=\"false\"")
      expect(body_text).to include("data-blacklisted=\"false\"")
    end

    it "hides every bulk action from a read-only user" do
      role = user.user_hotel_accesses.first.role
      role.permissions.destroy(Permission.find_by(slug: "manage_bookings"))

      get hotel_guests_path(hotel)

      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).not_to include("data-bulk-select-target=\"banner\"")
      expect(body_text).not_to include("Blacklist selected guests")
      expect(body_text).not_to include("Mark as VIP")
    end

    it "keeps the tab strip inside the frame the tabs replace" do
      get hotel_guests_path(hotel), params: { tag: "vip" }

      expect(response.body).to include("guests_results")
      frame = response.body[/<turbo-frame[^>]*guests_results.*?<\/turbo-frame>/m]
      expect(frame).to be_present
      # Outside the frame, a tab swaps the rows and leaves its own highlight
      # behind, and the filter form keeps posting the tab the user just left.
      expect(frame).to include("guest-tag-tabs")
      expect(frame).to match(/aria-current="page"[^>]*>(?:(?!<\/a>).)*VIP/m)
      expect(frame).to include("Search guests")
    end

    it "keeps the table and its headings when a filter finds nothing" do
      get hotel_guests_path(hotel), params: { query: "nobody-by-this-name" }

      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).to include("<table")
      expect(body_text).to include("Lifetime value")
      expect(body_text).to include("No guest records found")
      # The empty row stretches so the state sits in the middle of the card.
      expect(body_text).to match(/colspan="\d+" class="h-full align-middle"/)
    end

    it "scrolls the rows, not the page, so the tabs and filters stay put" do
      get hotel_guests_path(hotel)

      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).to include("panel-page--full-height")
      # The shell hands over its scroller, so the table has to own one.
      expect(body_text).not_to include("overflow-y-auto [scrollbar-gutter:stable]")
      expect(body_text).to include("panel-scroll-area__viewport")
      expect(body_text).to include("data-sticky-header=\"true\"")
      # The shell hands over its padding too, so the page applies its own.
      expect(body_text).to include(%(<div class="flex min-h-0 w-full flex-1 flex-col gap-4 p-2.5">))
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
        "document_type" => "passport",
        "government_id" => "p123456",
        "passport_number" => nil,
        "blacklisted" => false
      )
    end
  end

  describe "the shared action sheet" do
    let(:guest) { create(:guest, created_by_hotel: hotel) }

    it "serves new and edit as one sheet in the shell's frame" do
      get new_hotel_guest_path(hotel), params: { return_to: hotel_guests_path(hotel) }

      expect(response).to have_http_status(:success)
      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).to include(%(<turbo-frame id="settings_action_sheet">))
      expect(body_text).to include(%(<dialog id="new-guest-sheet"))
      expect(body_text).to include("panels-ui--sheet-frame")
      expect(body_text).to include("New guest record")
      expect(body_text).to include("Create guest record")
      # No page chrome: the sheet arrives on its own.
      expect(body_text).not_to include("<body")

      get edit_hotel_guest_path(hotel, guest)

      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).to include(%(<dialog id="edit-guest-sheet"))
      expect(body_text).to include("Edit guest record")
      expect(body_text).to include("Save changes")
      # One partial serves both, so both carry the same fields.
      expect(body_text).to include("Tax identification number")
      expect(body_text).to include("Identity verification")
    end

    it "orders the four sections and keeps date of birth with nationality" do
      get new_hotel_guest_path(hotel)

      body_text = CGI.unescapeHTML(response.body)
      headings = body_text.scan(%r{<h3 id="guest-[^"]+"[^>]*>([^<]+)</h3>}).flatten
      expect(headings).to eq([ "Basic information", "Address", "Identity verification", "Tax management" ])

      # guest-dob reads the nationality and writes the date of birth, so the two
      # sit in one row rather than two sections apart.
      basics = body_text[/guest-basics-heading.*?guest-address-heading/m]
      expect(basics).to include("Nationality")
      expect(basics).to include("Gender")
      expect(basics).to include("Date of birth")

      tax = body_text[/guest-tax-heading.*/m]
      expect(tax).to include("Tax identification number")
      expect(tax).to include("For example, IG5678901234")
    end

    it "uses the design system controls, not native selects" do
      get new_hotel_guest_path(hotel)

      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).to include("Select gender")
      expect(body_text).to include("Select document type")
      expect(body_text).to include("panel-select-menu")
      # Both country fields search the one shared list, the way the booking
      # guest forms already do.
      expect(body_text).to include("Search for a country")
      expect(body_text).to include(%(id="guest_country-combobox"))
      expect(body_text).to include(%(id="guest_address_country-combobox"))
      expect(body_text).to include(COUNTRY_OPTIONS.first)
    end

    it "closes the sheet at the page it was opened from" do
      post hotel_guests_path(hotel),
           params: { return_to: hotel_guests_path(hotel, tag: "vip"),
                     guest: { name: "Sheet Guest", email: "sheet@example.com", country: "Malaysia" } },
           headers: { "Accept" => Mime[:turbo_stream].to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("complete_sheet")
      expect(response.body).to include(hotel_guests_path(hotel, tag: "vip"))
      expect(flash[:notice]).to include("created successfully")
    end

    it "returns to the record page after an edit" do
      patch hotel_guest_path(hotel, guest),
            params: { return_to: details_hotel_guest_path(hotel, guest),
                      guest: { name: "Renamed Guest" } },
            headers: { "Accept" => Mime[:turbo_stream].to_s }

      expect(response.body).to include(details_hotel_guest_path(hotel, guest))
      expect(guest.reload.name).to eq("Renamed Guest")
    end

    # A destination that names a parent frame refreshes that frame alone. The
    # layout never re-renders with it, so the confirmation has to ride along in
    # the same response instead of waiting in the session.
    it "sends the confirmation with the response when only a frame reloads" do
      patch hotel_guest_path(hotel, guest),
            params: { return_to: details_hotel_guest_path(hotel, guest, parent_frame: "guest_record_page"),
                      guest: { name: "Framed Guest" } },
            headers: { "Accept" => Mime[:turbo_stream].to_s }

      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).to include("complete_sheet")
      expect(body_text).to include("parent_frame=guest_record_page")
      expect(body_text).to include("updated successfully")
      expect(flash[:notice]).not_to include("updated successfully")
    end

    it "keeps the confirmation in the flash when the whole page reloads" do
      patch hotel_guest_path(hotel, guest),
            params: { return_to: details_hotel_guest_path(hotel, guest),
                      guest: { name: "Whole Page Guest" } },
            headers: { "Accept" => Mime[:turbo_stream].to_s }

      expect(response.body).not_to include("parent_frame")
      expect(flash[:notice]).to include("updated successfully")
    end

    it "ignores a return_to that points off the property" do
      post hotel_guests_path(hotel),
           params: { return_to: "https://evil.example.com/steal",
                     guest: { name: "Sheet Guest", email: "safe@example.com", country: "Malaysia" } },
           headers: { "Accept" => Mime[:turbo_stream].to_s }

      expect(response.body).not_to include("evil.example.com")
      expect(response.body).to include(details_hotel_guest_path(hotel, Guest.last))
    end

    it "re-renders the sheet with the errors when the record will not save" do
      post hotel_guests_path(hotel), params: { guest: { name: "", country: "" } }

      expect(response).to have_http_status(:unprocessable_content)
      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).to include("Guest record could not be saved")
      expect(body_text).not_to include("<body")
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

  describe "PATCH /update with a section" do
    let(:guest) do
      create(:guest,
             created_by_hotel: hotel,
             name: "Ravi Menon",
             home_address: "No. 12, Jalan Ampang",
             city: "Kuala Lumpur",
             tin: "IG1111111111")
    end

    def save_section(section, attributes)
      patch hotel_guest_path(hotel, guest),
            params: { section: section, guest: attributes },
            headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
    end

    it "writes only the fields of the block that saved" do
      save_section("tax", tin: "IG2222222222")

      expect(response).to have_http_status(:success)
      expect(guest.reload.tin).to eq("IG2222222222")
      expect(guest.home_address).to eq("No. 12, Jalan Ampang")
      expect(guest.city).to eq("Kuala Lumpur")
    end

    it "ignores fields that belong to another block" do
      save_section("tax", tin: "IG3333333333", home_address: "Somewhere else")

      expect(guest.reload.tin).to eq("IG3333333333")
      expect(guest.home_address).to eq("No. 12, Jalan Ampang")
    end

    it "replaces the saved block alone" do
      save_section("address", city: "Kota Kinabalu")

      expect(guest.reload.city).to eq("Kota Kinabalu")
      expect(response.body).to include("guest_section_address")
      expect(response.body).not_to include("guest_section_tax")
    end

    it "refreshes the header when the identity block saves" do
      save_section("identity", name: "Ravi Menon Jr")

      expect(guest.reload.name).to eq("Ravi Menon Jr")
      expect(response.body).to include("guest-record-header")
    end

    it "leaves the header alone when another block saves" do
      save_section("address", city: "Kota Kinabalu")

      expect(response.body).not_to include("guest-record-header")
    end

    it "re-renders the block with its errors when the save fails" do
      save_section("identity", name: "")

      expect(response).to have_http_status(:unprocessable_content)
      expect(guest.reload.name).to eq("Ravi Menon")
      expect(CGI.unescapeHTML(response.body)).to include("This section could not be saved")
    end

    it "rejects a section name it does not know" do
      save_section("payroll", tin: "IG4444444444")

      expect(response).to have_http_status(:not_found)
      expect(guest.reload.tin).to eq("IG1111111111")
    end
  end

  describe "the city field" do
    it "offers the property's city as a placeholder rather than a prefilled value" do
      hotel.update!(city: "Langkawi")

      get new_hotel_guest_path(hotel)

      city = response.parsed_body.at_css("input[name='guest[city]']")
      expect(city[:value]).to be_blank
      expect(city[:placeholder]).to eq("For example, Langkawi")
    end
  end

  describe "the address block's state field" do
    it "opens on the property's country, so an unfilled address gets the state list" do
      guest = create(:guest, created_by_hotel: hotel, address_country: nil, country: "Malaysia")

      get details_hotel_guest_path(hotel, guest)

      document = response.parsed_body
      coded = document.at_css("[data-address-state-target='coded']")
      free = document.at_css("[data-address-state-target='free']")

      expect(coded[:hidden]).to be_nil
      expect(coded.at_css("select")[:disabled]).to be_nil
      expect(free[:hidden]).to be_present
    end

    it "leaves a foreign address on the free text box" do
      guest = create(:guest, created_by_hotel: hotel, address_country: "Japan", country: "Japan")

      get details_hotel_guest_path(hotel, guest)

      document = response.parsed_body
      expect(document.at_css("[data-address-state-target='coded']")[:hidden]).to be_present
      expect(document.at_css("[data-address-state-target='free']")[:hidden]).to be_nil
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
      expect(body_text).to include("Identity verification")
      expect(body_text).to include("Guest address")
      expect(body_text).to include("Tax management")
      expect(body_text).to include("Total stays")
      expect(body_text.downcase).to include("india")
      expect(body_text).to include("No. 12, Jalan Ampang")

      get booking_history_hotel_guest_path(hotel, guest)
      body_text = CGI.unescapeHTML(response.body)

      expect(response).to have_http_status(:success)
      expect(body_text).to include("Lifetime value")
      expect(body_text).to include("<tfoot>")
      # The stays table scrolls inside 80dvh rather than running past the fold.
      expect(body_text).to include("max-h-[80dvh]")
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

    # The record sits in the guest_record_page frame. A link that stayed inside
    # it would pull the directory into a frame the directory does not have, and
    # Turbo would leave the reader with an empty panel.
    # The breadcrumb bar lives in the layout, so the trail can only follow the
    # tab while the tabs reload the page rather than one frame inside it.
    it "names the open tab in the breadcrumb trail" do
      get details_hotel_guest_path(hotel, guest)
      trail = response.parsed_body.at_css(".portal-breadcrumb-bar").text.squish
      expect(trail).to include("Ravi Menon")
      expect(trail).not_to include("Booking History")

      get booking_history_hotel_guest_path(hotel, guest)
      trail = response.parsed_body.at_css(".portal-breadcrumb-bar").text.squish
      expect(trail).to include("Ravi Menon")
      expect(trail).to include("Booking History")
    end

    # The strip is inside the record frame, so an untargeted link would swap the
    # frame and leave the URL and the shell where they were.
    it "sends the tab links to the page, not to the record frame" do
      get details_hotel_guest_path(hotel, guest)

      document = response.parsed_body
      %w[details booking_history].each do |tab|
        link = document.at_css("#guest-record-tabs-tab-#{tab}")
        expect(link["data-turbo-frame"]).to eq("_top")
      end
    end

    it "sends Back and Delete out of the record frame" do
      access = UserHotelAccess.find_by(user: user, hotel: hotel)
      access.role.permissions << (Permission.find_by(slug: "delete_guest_record") || create(:permission, slug: "delete_guest_record"))

      get details_hotel_guest_path(hotel, guest)

      document = response.parsed_body
      back = document.at_css("a[href='#{hotel_guests_path(hotel)}'][aria-label='Back to Guest Records']")
      expect(back["data-turbo-frame"]).to eq("_top")

      # Delete is a button_to, so the frame target belongs on its form. The four
      # section forms post to the same path, so pick the one carrying DELETE.
      delete = document.css("form[action='#{hotel_guest_path(hotel, guest)}']").find do |form|
        form.at_css("input[name='_method'][value='delete']")
      end
      expect(delete["data-turbo-frame"]).to eq("_top")
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

    # The badges are the at-a-glance marker beside the name. The status cards
    # carry the same state with its detail; both are wanted.
    it "shows the status badges in the header and again in the status cards" do
      Guests::SetVip.new(guests: guest, hotel: hotel, vip: true).call
      Guests::SetBlacklist.new(guests: guest, hotel: hotel, blacklisted: true, actor: user, reason: "Damaged the room").call

      get details_hotel_guest_path(hotel, guest)

      body_text = CGI.unescapeHTML(response.body)
      header = body_text[/<header[^>]*data-testid="guest-record-header"[\s\S]*?<\/header>/]
      expect(header).to include("VIP")
      expect(header).to include("Blacklisted")

      expect(body_text).to include("VIP at #{hotel.name}")
      expect(body_text).to include("Damaged the room")
    end

    # The outer frame carries the header. An edit that renames the guest has to
    # refresh the name and badges above the tabs, not only the tab body.
    it "returns the header as well to the outer record frame" do
      get details_hotel_guest_path(hotel, guest), headers: { "Turbo-Frame" => "guest_record_page" }

      expect(response).to have_http_status(:success)
      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).to include("guest_record_page")
      expect(body_text).to include("guest-record-header")
      expect(body_text).to include("Guest identity")
    end

    it "marks the tab it renders as the current one" do
      get details_hotel_guest_path(hotel, guest)
      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).to match(/id="guest-record-tabs-tab-details"[^>]*aria-current="page"/)
      expect(body_text).not_to match(/id="guest-record-tabs-tab-booking_history"[^>]*aria-current="page"/)

      get booking_history_hotel_guest_path(hotel, guest)
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

  describe "bulk status actions" do
    let!(:vip_guest) { create(:guest, created_by_hotel: hotel) }
    let!(:plain_guest) { create(:guest, created_by_hotel: hotel) }
    let(:other_hotel_guest) { create(:guest) }

    before { Guests::SetVip.new(guests: vip_guest, hotel: hotel, vip: true).call }

    def ids(*guests) = { guest_ids: guests.map(&:id).to_json }

    it "marks every selected record VIP and skips the ones already VIP" do
      patch bulk_vip_hotel_guests_path(hotel), params: ids(vip_guest, plain_guest)

      expect(response).to have_http_status(:see_other)
      expect(flash[:notice]).to include("1 guest record marked as VIP")
      expect(plain_guest.reload.vip_at?(hotel)).to be true
      expect(vip_guest.reload.vip_at?(hotel)).to be true
    end

    it "removes VIP from the selection" do
      patch bulk_unvip_hotel_guests_path(hotel), params: ids(vip_guest, plain_guest)

      expect(flash[:notice]).to include("VIP removed from 1 guest record")
      expect(vip_guest.reload.vip_at?(hotel)).to be false
    end

    it "blacklists the selection under one shared reason" do
      patch bulk_blacklist_hotel_guests_path(hotel),
            params: ids(vip_guest, plain_guest).merge(blacklist_reason: "Group no-show")

      expect(flash[:notice]).to include("2 guest records blacklisted")
      [ vip_guest, plain_guest ].each do |guest|
        expect(guest.reload.blacklisted_at?(hotel)).to be true
        expect(guest.blacklist_detail(hotel)["reason"]).to eq("Group no-show")
        expect(guest.blacklist_detail(hotel)["blacklisted_by_id"]).to eq(user.id)
      end
    end

    it "refuses a bulk blacklist with no reason" do
      patch bulk_blacklist_hotel_guests_path(hotel), params: ids(plain_guest)

      expect(flash[:alert]).to include("provide a reason")
      expect(plain_guest.reload.blacklisted_at?(hotel)).to be false
    end

    it "clears the blacklist across the selection" do
      Guests::SetBlacklist.new(guests: [ vip_guest ], hotel: hotel, blacklisted: true, actor: user, reason: "Damage").call

      patch bulk_unblacklist_hotel_guests_path(hotel), params: ids(vip_guest, plain_guest)

      expect(flash[:notice]).to include("Blacklist removed from 1 guest record")
      expect(vip_guest.reload.blacklisted_at?(hotel)).to be false
    end

    it "ignores a record this property cannot read" do
      patch bulk_vip_hotel_guests_path(hotel), params: ids(other_hotel_guest)

      expect(flash[:alert]).to include("No guest records selected")
      expect(other_hotel_guest.reload.vip_at?(hotel)).to be false
    end

    it "survives a malformed selection" do
      patch bulk_vip_hotel_guests_path(hotel), params: { guest_ids: "not json" }

      expect(response).to have_http_status(:see_other)
      expect(flash[:alert]).to include("No guest records selected")
    end

    it "returns to the tab the action was fired from" do
      patch bulk_vip_hotel_guests_path(hotel), params: ids(plain_guest).merge(tag: "vip")

      expect(response).to redirect_to(hotel_guests_path(hotel, tag: "vip"))
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
