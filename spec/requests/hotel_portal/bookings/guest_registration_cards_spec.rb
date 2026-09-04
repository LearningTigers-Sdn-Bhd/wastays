require "rails_helper"
require "cgi"

RSpec.describe "HotelPortal::Bookings::GuestRegistrationCards", type: :request do
  let(:hotel) { create(:hotel, status: "live", guest_registration_card_terms: "Valid photo ID is required at check-in.") }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }
  let(:booking) { create(:booking, hotel: hotel) }

  before do
    %w[manage_bookings view_bookings].each do |slug|
      role.permissions << (Permission.find_by(slug: slug) || create(:permission, slug: slug))
    end
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  def grant_permission(slug)
    permission = Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.humanize }
    role.permissions << permission unless role.permissions.exists?(permission.id)
  end

  describe "GET /hotel/:hotel_id/bookings/:booking_id/guest_registration_card" do
    it "creates a draft card on first open and shows the pending registration number" do
      get hotel_booking_guest_registration_card_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Guest Registration No.")
      expect(response.body).to include("Pending check-in")
      expect(response.body).to include("Please read the terms and conditions carefully before signing")
      expect(response.body.scan("Print official form").size).to eq(1)
      expect(response.body).not_to include("Hotel acknowledgement")
      expect(response.body).not_to include("Cancellation Policy")
    end

    it "shows the hotel's registration number and SST" do
      hotel.update!(ssm_number: "SSM-12345", sst_registration_number: "SST-67890")

      get hotel_booking_guest_registration_card_path(hotel, booking)

      expect(response.body).to include("Reg. No: SSM-12345", "SST: SST-67890")
    end

    it "shows formatted guest registration number after check-in number exists" do
      year = hotel.current_business_date.year
      booking.update!(guest_registration_number: 1, guest_registration_year: year)

      get hotel_booking_guest_registration_card_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("#{hotel.hotel_prefix}-#{year.to_s.last(2)}200001")
    end

    it "links the official print button to the GRC PDF preview" do
      get hotel_booking_guest_registration_card_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include('data-official-print="true"')
      expect(response.body.scan("Print official form").size).to eq(1)
      expect(response.body).to include(hotel_booking_guest_registration_card_pdf_path(hotel, booking))
      expect(response.body).to include("grc-print grc-print-page")
    end

    it "warns about an unpaid balance without blocking document actions" do
      booking.update!(total_amount: 138.24)

      get hotel_booking_guest_registration_card_path(hotel, booking)

      document = Nokogiri::HTML(response.body)
      alert = document.at_css(".panel-alert[data-tone='warning']")
      expect(alert.text.squish).to include(
        "Outstanding balance: MYR 138.24",
        "If payment has already been received, record it before printing or emailing this card.",
        "Ask an authorized staff member to record the payment."
      )
      expect(alert.at_css("a")).to be_nil
      expect(response.body).to include("Print official form", "Email to guest", "Save Signature")
      expect(document.at_css("article.grc-print").text).not_to include("Outstanding balance:")
    end

    it "offers the existing payment sheet with the remaining balance prefilled" do
      grant_permission("post_folio_payments")
      booking.update!(total_amount: 138.24)
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "booking_payment", amount: 50)

      get hotel_booking_guest_registration_card_path(hotel, booking)

      document = Nokogiri::HTML(response.body)
      alert = document.at_css(".panel-alert[data-tone='warning']")
      link = alert.at_xpath(".//a[contains(., 'Add Payment')]")
      expect(alert.text.squish).to include("Outstanding balance: MYR 88.24")
      expect(link["href"]).to eq(hotel_folio_action_post_transaction_path(
        hotel,
        booking,
        transaction_type: "payment",
        active_folio_id: folio.id,
        amount: "88.24",
        return_to: hotel_booking_guest_registration_card_path(hotel, booking)
      ))
      expect(link["data-turbo-frame"]).to eq("folio_action_sheet")
    end

    it "removes the warning when payments cover the booking total" do
      booking.update!(total_amount: 138.24)
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "booking_payment", amount: 138.24)

      get hotel_booking_guest_registration_card_path(hotel, booking)

      expect(response.body).not_to include("Outstanding balance:", "Add Payment")
      expect(response.body).to include("Due amount", "MYR 0.00", "Print official form")
    end

    it "returns from a posted payment to a refreshed settled card" do
      grant_permission("post_folio_payments")
      booking.update!(total_amount: 138.24)
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      PaymentMethods::EnsureDefaults.call(hotel)
      payment_method = hotel.hotel_payment_methods.joins(:transaction_code)
        .find_by!(transaction_codes: { system_key: "cash_payment" })
      return_to = hotel_booking_guest_registration_card_path(hotel, booking)

      post hotel_folio_action_post_transaction_path(hotel, booking), params: {
        return_to: return_to,
        folio_transaction: {
          transaction_type: "payment",
          booking_folio_id: folio.id,
          hotel_payment_method_id: payment_method.id,
          amount: "138.24",
          description: "Payment received at front desk",
          posting_date: hotel.current_business_date
        }
      }

      expect(response).to redirect_to(return_to)
      follow_redirect!
      expect(response.body).not_to include("Outstanding balance:", "Add Payment")
      expect(response.body).to include("Amount paid", "MYR 138.24", "Due amount", "MYR 0.00")
    end

    it "shows profile managers where to configure displayed details" do
      role.permissions << (Permission.find_by(slug: "manage_hotel_profile") || create(:permission, slug: "manage_hotel_profile"))

      get hotel_booking_guest_registration_card_path(hotel, booking)

      actions = Nokogiri::HTML(response.body).at_css("aside section")
      expect(actions.text).to include("Configure displayed details")
      configure_link = actions.at_xpath(".//a[contains(., 'Configure displayed details')]")
      expect(configure_link["href"]).to eq("#{hotel_settings_path(hotel, tab: "general")}#guest-registration-card")
    end

    it "hides display configuration from staff without profile permission" do
      get hotel_booking_guest_registration_card_path(hotel, booking)

      expect(response.body).not_to include("Configure displayed details")
    end

    it "renders primary stay snapshot details instead of later profile changes" do
      guest = create(:guest, name: "Profile Name", email: "profile@example.com", phone: "111", country: "Singapore")
      create(
        :booking_guest,
        booking: booking,
        guest: guest,
        is_primary: true,
        name_snapshot: "Stay Name",
        email_snapshot: "stay@example.com",
        phone_snapshot: "222",
        country_snapshot: "Malaysia"
      )

      get hotel_booking_guest_registration_card_path(hotel, booking)

      expect(response.body).to include("Stay Name", "stay@example.com", "222", "Malaysia")
      expect(response.body).not_to include("Profile Name", "profile@example.com", "Singapore")
    end

    it "renders the additional guest details when booking_guest_id parameter is passed" do
      primary = booking.booking_guests.find(&:primary?) || create(:booking_guest, booking: booking, is_primary: true)
      primary.update!(
        name_snapshot: "Primary Guest",
        email_snapshot: "primary@example.com",
        phone_snapshot: "111111",
        country_snapshot: "Malaysia"
      )

      additional = create(
        :booking_guest,
        booking: booking,
        is_primary: false,
        name_snapshot: "Additional Guest",
        email_snapshot: "additional@example.com",
        phone_snapshot: "999999",
        country_snapshot: "Singapore"
      )
      booking.booking_guests.reload

      get hotel_booking_guest_registration_card_path(hotel, booking, booking_guest_id: additional.id)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Additional Guest", "additional@example.com", "999999", "Singapore")
      expect(response.body).not_to include("primary@example.com", "111111")
    end

    it "hides the boat transfer section when the guest has no boat data" do
      get hotel_booking_guest_registration_card_path(hotel, booking)

      expect(response.body).not_to include("Boat-in")
      expect(response.body).not_to include("Boat-out")
    end

    it "shows the primary guest's boat transfer times on screen and print card" do
      hotel.update!(time_zone: "Asia/Kuala_Lumpur")
      create(
        :booking_guest,
        booking: booking,
        is_primary: true,
        boat_in_at: ActiveSupport::TimeZone["Asia/Kuala_Lumpur"].parse("2026-08-01 08:00"),
        boat_out_at: ActiveSupport::TimeZone["Asia/Kuala_Lumpur"].parse("2026-08-05 15:30")
      )

      get hotel_booking_guest_registration_card_path(hotel, booking)

      document = Nokogiri::HTML(response.body)
      [ document.at_css("section.grc-no-print"), document.at_css("article.grc-print") ].each do |card|
        text = card.text
        expect(text).to include("Boat-in", "01 Aug 2026, 08:00 AM")
        expect(text).to include("Boat-out", "05 Aug 2026, 03:30 PM")
      end
    end

    it "shows room type by default on screen and print card" do
      room_type = create(:room_type, hotel: hotel, name: "Deluxe King")
      create(:booking_room, booking: booking, room_type: room_type)

      get hotel_booking_guest_registration_card_path(hotel, booking)

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("section.grc-no-print").text).to include("Room type", "Deluxe King")
      expect(document.at_css("article.grc-print").text).to include("Room type", "Deluxe King")
    end

    it "hides disabled fields on draft screen and print card" do
      hotel.update!(guest_registration_card_fields: %w[room_type check_in check_out])

      get hotel_booking_guest_registration_card_path(hotel, booking)

      document = Nokogiri::HTML(response.body)
      [ document.at_css("section.grc-no-print"), document.at_css("article.grc-print") ].each do |card|
        labels = card.css("dt").map { |node| node.text.strip }
        expect(labels).to include("Name", "Room type", "Check-in", "Check-out")
        expect(labels).not_to include("Phone", "Email", "Guests", "Room(s)", "Booking")
      end
      expect(document.at_css("section.grc-no-print").text).not_to include("Booking #{booking.confirmation_token}")
    end

    it "keeps signed fields after hotel settings change" do
      card = create(:guest_registration_card, :signed, booking: booking, hotel: hotel, display_fields_snapshot: %w[email room_type])
      hotel.update!(guest_registration_card_fields: %w[phone check_in])

      get hotel_booking_guest_registration_card_path(hotel, booking)

      document = Nokogiri::HTML(response.body)
      [ document.at_css("section.grc-no-print"), document.at_css("article.grc-print") ].each do |rendered_card|
        labels = rendered_card.css("dt").map { |node| node.text.strip }
        expect(labels).to include("Email", "Room type")
        expect(labels).not_to include("Phone", "Check-in")
      end
      expect(card.reload.display_fields_snapshot).to eq(%w[email room_type])
    end

    it "renders the booking's special requests as Remark, with check-in/check-out times combined into the date" do
      create(:property_policy, hotel: hotel, check_in_time: "3:00 PM", check_out_time: "11:00 AM")
      booking.update!(special_requests: "Please provide a quiet room.", internal_notes: "VIP guest, prioritize service.")

      get hotel_booking_guest_registration_card_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Remark")
      expect(response.body).to include("Please provide a quiet room.")
      expect(response.body).not_to include("Check-in time")
      expect(response.body).not_to include("Check-out time")
      expect(response.body).to include("3:00 PM")
      expect(response.body).to include("11:00 AM")

      document = Nokogiri::HTML(response.body)
      remark_textarea = document.at_css("textarea[data-registration-card-target='remarkInput']")
      expect(remark_textarea).to be_present
      expect(remark_textarea.text.strip).to eq("Please provide a quiet room.")

      remark_print = document.at_css("div[data-registration-card-target='remarkPrint']")
      expect(remark_print).to be_present
      expect(remark_print.text.strip).to eq("Please provide a quiet room.")
    end

    it "does not render Please Note or a way to manage note templates" do
      booking.update!(internal_notes: "VIP guest, prioritize service.")

      get hotel_booking_guest_registration_card_path(hotel, booking)

      expect(response.body).not_to include("Please Note")
      expect(response.body).not_to include("VIP guest, prioritize service.")
      expect(response.body).not_to include("Manage note templates")
    end

    it "renders the hotel's fixed Terms & Conditions" do
      get hotel_booking_guest_registration_card_path(hotel, booking)

      expect(response.body).to include("Terms &amp; Conditions")
      expect(response.body).to include("Valid photo ID is required at check-in.")
    end
  end

  describe "PATCH /hotel/:hotel_id/bookings/:booking_id/guest_registration_card" do
    it "saves signature and terms snapshot" do
      create(:property_policy, hotel: hotel, check_in_time: "3:00 PM", check_out_time: "11:00 AM", cancellation_policy: "No refund after check-in")

      patch hotel_booking_guest_registration_card_path(hotel, booking), params: {
        guest_registration_card: {
          signer_name: "Jane Guest",
          signature_data_url: "data:image/png;base64,abc123",
          special_requests: "Please provide double pillows.",
          internal_notes: "VIP guest, likes quiet."
        }
      }

      card = booking.reload.guest_registration_card
      expect(response).to redirect_to(hotel_booking_guest_registration_card_path(hotel, booking))
      expect(card).to be_signed
      expect(card.signer_name).to eq("Jane Guest")
      expect(card.signature_data_url).to eq("data:image/png;base64,abc123")
      expect(card.signed_at).to be_present
      expect(card.terms_snapshot).to include("check_in_time" => "3:00 PM", "check_out_time" => "11:00 AM", "cancellation_policy" => "No refund after check-in")

      expect(booking.special_requests).to eq("Please provide double pillows.")
      expect(booking.internal_notes).to eq("VIP guest, likes quiet.")
    end

    it "saves remarks and notes separately via JSON format (auto-save)" do
      patch hotel_booking_guest_registration_card_path(hotel, booking, format: :json), params: {
        guest_registration_card: {
          special_requests: "Need extra towels.",
          internal_notes: "Regular guest."
        }
      }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("success")
      expect(json["message"]).to eq("Remarks and notes updated.")
      expect(booking.reload.special_requests).to eq("Need extra towels.")
      expect(booking.internal_notes).to eq("Regular guest.")
      expect(booking.guest_registration_card).not_to be_signed
    end

    it "allows auto-saving remarks and notes via JSON format even if the card is signed" do
      card = create(:guest_registration_card, :signed, booking: booking, hotel: hotel)

      patch hotel_booking_guest_registration_card_path(hotel, booking, format: :json), params: {
        guest_registration_card: {
          special_requests: "Changed pillow preference.",
          internal_notes: "Updated priority."
        }
      }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("success")
      expect(json["message"]).to eq("Remarks and notes updated.")
      expect(booking.reload.special_requests).to eq("Changed pillow preference.")
      expect(booking.internal_notes).to eq("Updated priority.")
      expect(card.reload).to be_signed
    end

    it "rejects blank signature" do
      patch hotel_booking_guest_registration_card_path(hotel, booking), params: {
        guest_registration_card: {
          signer_name: "Jane Guest",
          signature_data_url: ""
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(CGI.unescapeHTML(response.body)).to include("Signature data url can't be blank")
      expect(response.body).not_to include("Signed by Jane Guest")
    end

    it "snapshots visible fields when signed" do
      hotel.update!(guest_registration_card_fields: %w[email room_type])

      patch hotel_booking_guest_registration_card_path(hotel, booking), params: {
        guest_registration_card: {
          signer_name: "Jane Guest",
          signature_data_url: "data:image/png;base64,abc123"
        }
      }

      expect(booking.reload.guest_registration_card.display_fields_snapshot).to eq(%w[email room_type])
    end

    it "does not modify an already-signed card" do
      card = create(
        :guest_registration_card,
        :signed,
        booking: booking,
        hotel: hotel,
        signer_name: "Original Guest",
        signature_data_url: "data:image/png;base64,original",
        signed_at: 1.day.ago,
        terms_snapshot: { "cancellation_policy" => "Original policy" },
        display_fields_snapshot: %w[email room_type]
      )
      original_attributes = card.attributes.slice(
        "signature_data_url", "signer_name", "signed_at", "terms_snapshot", "display_fields_snapshot"
      )
      hotel.update!(guest_registration_card_fields: %w[phone check_in])
      create(:property_policy, hotel: hotel, cancellation_policy: "Changed policy")

      patch hotel_booking_guest_registration_card_path(hotel, booking), params: {
        guest_registration_card: {
          signer_name: "Replacement Guest",
          signature_data_url: "data:image/png;base64,replacement"
        }
      }

      expect(response).to redirect_to(hotel_booking_guest_registration_card_path(hotel, booking))
      expect(flash[:alert]).to eq("Delete the existing signature before signing again.")
      expect(card.reload.attributes.slice(*original_attributes.keys)).to eq(original_attributes)
    end

    it "does not overwrite a card signed by a contender before locking" do
      card = create(:guest_registration_card, booking: booking, hotel: hotel)
      signed_at = 1.minute.ago
      expect_any_instance_of(GuestRegistrationCard).to receive(:lock!).and_wrap_original do |method|
        GuestRegistrationCard.where(id: method.receiver.id).update_all(
          status: "signed",
          signer_name: "First Guest",
          signature_data_url: "data:image/png;base64,first",
          signed_at: signed_at
        )
        method.call
      end

      patch hotel_booking_guest_registration_card_path(hotel, booking), params: {
        guest_registration_card: {
          signer_name: "Second Guest",
          signature_data_url: "data:image/png;base64,second"
        }
      }

      expect(response).to redirect_to(hotel_booking_guest_registration_card_path(hotel, booking))
      expect(flash[:alert]).to eq("Delete the existing signature before signing again.")
      card.reload
      expect(card).to have_attributes(
        signer_name: "First Guest",
        signature_data_url: "data:image/png;base64,first"
      )
      expect(card.signed_at).to be_within(0.000001.seconds).of(signed_at)
    end
  end

  describe "DELETE /hotel/:hotel_id/bookings/:booking_id/guest_registration_card" do
    it "clears a saved signature so the guest can sign again or sign physically" do
      card = create(:guest_registration_card, :signed, booking: booking, hotel: hotel)

      delete hotel_booking_guest_registration_card_path(hotel, booking)

      expect(response).to redirect_to(hotel_booking_guest_registration_card_path(hotel, booking))
      expect(card.reload).to be_draft
      expect(card.signer_name).to be_blank
      expect(card.signature_data_url).to be_blank
      expect(card.signed_at).to be_blank

      hotel.update!(guest_registration_card_fields: %w[phone check_in])
      get hotel_booking_guest_registration_card_path(hotel, booking)

      document = Nokogiri::HTML(response.body)
      [ document.at_css("section.grc-no-print"), document.at_css("article.grc-print") ].each do |rendered_card|
        labels = rendered_card.css("dt").map { |node| node.text.strip }
        expect(labels).to include("Phone", "Check-in")
        expect(labels).not_to include("Email")
      end
    end
  end

  describe "when the hotel has not set its Terms & Conditions" do
    let(:hotel) { create(:hotel, status: "live", guest_registration_card_terms: nil) }

    it "shows the setup banner and hides signing and sending" do
      get hotel_booking_guest_registration_card_path(hotel, booking)

      expect(response.body).to include("Terms &amp; Conditions required")
      expect(response.body).not_to include("Save Signature")
      expect(response.body.scan("Print official form").size).to eq(0)
    end

    it "refuses to print" do
      get hotel_booking_guest_registration_card_pdf_path(hotel, booking)

      expect(response).to redirect_to(hotel_booking_guest_registration_card_path(hotel, booking))
      follow_redirect!
      expect(response.body).to include("before printing this card")
    end
  end

  describe "booking documents" do
    it "links to the guest registration card from booking show" do
      get hotel_booking_workspace_path(hotel, booking, tab: "guest_details")

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-testid="booking-workspace"')
      expect(response.body).to include("Guests")
    end
  end
end
