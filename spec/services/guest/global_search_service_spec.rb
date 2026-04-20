require "rails_helper"

RSpec.describe Guest::GlobalSearchService do
  include Rails.application.routes.url_helpers

  let(:guest) do
    create(:guest,
           name: "Search Guest",
           email: "search.guest@example.com",
           phone: "+60123456789",
           country: "Malaysia",
           document_type: "passport",
           government_id: "A1234567")
  end

  let(:hotel) { create(:hotel, name: "Ocean Bay Resort") }

  describe "#perform" do
    it "returns guest page entries for empty query" do
      results = described_class.new(guest, "").perform

      expect(results).to include(
        hash_including(title: "Guest Dashboard", group: "Pages", url: guest_dashboard_path),
        hash_including(title: "My Bookings", group: "Pages", url: guest_bookings_path)
      )
    end

    it "returns booking matches linked to the guest" do
      booking = create(:booking,
                       hotel: hotel,
                       guest_name: "Alicia Tan",
                       guest_email: "alicia@example.com",
                       confirmation_token: "WS-ALICIA01")
      create(:booking_guest, booking: booking, guest: guest, is_primary: true)

      other_guest = create(:guest,
                           name: "Other Guest",
                           email: "other@example.com",
                           phone: "+60111111111",
                           country: "Malaysia",
                           document_type: "passport",
                           government_id: "B7654321")
      other_booking = create(:booking, hotel: hotel, guest_name: "Other Person", confirmation_token: "WS-OTHER99")
      create(:booking_guest, booking: other_booking, guest: other_guest, is_primary: true)

      results = described_class.new(guest, "alicia").perform

      expect(results).to include(hash_including(title: a_string_including("WS-ALICIA01"), group: "Bookings", url: guest_booking_path(booking)))
      expect(results).not_to include(hash_including(title: a_string_including("WS-OTHER99")))
    end
  end

  describe "#quick_actions" do
    it "returns guest quick actions" do
      actions = described_class.new(guest, "").quick_actions

      expect(actions).to include(
        { group: "Bookings", label: "Go to bookings", url: guest_bookings_path },
        { group: "Pages", label: "Go to dashboard", url: guest_dashboard_path }
      )
    end
  end
end
