require "rails_helper"
require "cgi"

RSpec.describe "HotelPortal::Bookings::GuestRegistrationCards", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
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

  describe "GET /hotel/:hotel_id/bookings/:booking_id/guest_registration_card" do
    it "creates a draft card on first open and shows guest registration number" do
      get hotel_booking_guest_registration_card_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(booking.reload.guest_registration_card).to be_present
      expect(response.body).to include("GRC / Guest Registration No")
      expect(response.body).to include(booking.formatted_guest_registration_number)
      expect(response.body).to include("Please read the terms and conditions carefully before signing")
      expect(response.body.scan("Print official form").size).to eq(1)
      expect(response.body).not_to include("Hotel acknowledgement")
      expect(response.body).not_to include("Cancellation Policy")
    end

    it "shows formatted guest registration number after check-in number exists" do
      booking.update!(guest_registration_number: 1)

      get hotel_booking_guest_registration_card_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("#{hotel.hotel_prefix}-20000001")
    end

    it "keeps the existing official print button and printable document" do
      get hotel_booking_guest_registration_card_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include('data-official-print="true"')
      expect(response.body.scan("Print official form").size).to eq(1)
      expect(response.body).to include('onclick="window.print()"')
      expect(response.body).to include("grc-print grc-print-page")
    end

    it "shows profile managers where to configure displayed details" do
      role.permissions << (Permission.find_by(slug: "manage_hotel_profile") || create(:permission, slug: "manage_hotel_profile"))

      get hotel_booking_guest_registration_card_path(hotel, booking)

      actions = Nokogiri::HTML(response.body).at_css("aside section")
      expect(actions.text).to include("Configure displayed details")
      expect(actions.at_xpath("./a")["href"]).to eq("#{hotel_settings_path(hotel, tab: "general")}#guest-registration-card")
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

    it "renders the booking's special requests as Remark and internal notes as Notes under check-in time" do
      create(:property_policy, hotel: hotel, check_in_time: "3:00 PM", check_out_time: "11:00 AM")
      booking.update!(special_requests: "Please provide a quiet room.", internal_notes: "VIP guest, prioritize service.")

      get hotel_booking_guest_registration_card_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Remark")
      expect(response.body).to include("Please provide a quiet room.")
      expect(response.body).to include("Notes")
      expect(response.body).to include("VIP guest, prioritize service.")
    end
  end

  describe "PATCH /hotel/:hotel_id/bookings/:booking_id/guest_registration_card" do
    it "saves signature and terms snapshot" do
      create(:property_policy, hotel: hotel, check_in_time: "3:00 PM", check_out_time: "11:00 AM", cancellation_policy: "No refund after check-in")

      patch hotel_booking_guest_registration_card_path(hotel, booking), params: {
        guest_registration_card: {
          signer_name: "Jane Guest",
          signature_data_url: "data:image/png;base64,abc123"
        }
      }

      card = booking.reload.guest_registration_card
      expect(response).to redirect_to(hotel_booking_guest_registration_card_path(hotel, booking))
      expect(card).to be_signed
      expect(card.signer_name).to eq("Jane Guest")
      expect(card.signature_data_url).to eq("data:image/png;base64,abc123")
      expect(card.signed_at).to be_present
      expect(card.terms_snapshot).to include("check_in_time" => "3:00 PM", "check_out_time" => "11:00 AM", "cancellation_policy" => "No refund after check-in")
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

  describe "booking documents" do
    it "links to the guest registration card from booking show" do
      get hotel_booking_control_panel_path(hotel, booking, tab: "guest_details")

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-testid="booking-control-panel"')
      expect(response.body).to include("Guest Details")
    end
  end
end
