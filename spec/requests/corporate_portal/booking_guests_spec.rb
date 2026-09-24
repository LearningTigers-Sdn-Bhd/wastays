# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CorporatePortal booking guests", type: :request do
  let(:user) { create(:user, :corporate) }
  let(:hotel) { create(:hotel, status: "live") }
  let(:relationship) do
    create(:hotel_corporate_account, corporate_account: user.account, hotel: hotel, agent_booking_enabled: true)
  end
  let!(:room_type) do
    Rooms::SaveSeedRoomType.call!(
      hotel: hotel,
      attributes: { name: "Deluxe", room_number_mode: "custom", quantity: 4, base_price: 250.0,
                    max_adults: 3, max_children: 2, room_numbers: %w[101 102 103 104] }
    )
  end
  let(:check_in) { Date.current + 14 }
  let(:check_out) { Date.current + 16 }

  before do
    relationship
    sign_in_as(user)
  end

  def book(agent_reference: "TRV-0142")
    post corporate_bookings_path, params: {
      hotel_relationship_id: relationship.id,
      booking: {
        room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
        adults: 2, children: 0, rooms: 1, agent_reference: agent_reference, special_requests: "Sea view please",
        rooms_detail: { "0" => { guests: { "0" => { name: "Aisha Rahman", phone: "+60123456789", email: "aisha@example.com",
                                                     country: "Singapore", government_id: "K1234567", date_of_birth: "1990-04-02" } } } }
      }
    }
    Booking.order(:id).last
  end

  it "shows the agent what they sold and who is staying, with the ID masked" do
    booking = book

    get corporate_booking_path(booking)

    card = response.parsed_body.at_css('[data-testid="agent-room-detail"]').text.squish
    expect(card).to include("Deluxe", "Corporate Rate", "Aisha Rahman", "Lead guest", "Singapore", "+60123456789",
                            "•••• 567", "Sea view please", "Nightly rates", "Edit guests")
    expect(response.body).not_to include("K1234567")
    expect(response.body).to include("Your reference", "TRV-0142")
  end

  it "lets the agent correct the lead guest before arrival and records it for the hotel" do
    booking = book
    lead = booking.booking_guests.find_by!(is_primary: true)

    patch corporate_booking_guests_path(booking), params: {
      guests: { lead.id.to_s => { name: "Aisha binti Rahman", phone: "+60199999999", email: "aisha@example.com",
                                  country: "Singapore", government_id: "", date_of_birth: "1990-04-02" } }
    }

    expect(response).to redirect_to(corporate_booking_path(booking))
    expect(booking.reload.guest_name).to eq("Aisha binti Rahman")
    expect(booking.guest_phone).to eq("+60199999999")
    # Kept, not wiped by the blank field (Guest stores passport numbers lowercased).
    expect(lead.reload.passport_number_snapshot).to eq("k1234567")

    log = BookingAuditLog.where(auditable: booking, action_type: "guest_updated").sole
    expect(log).to have_attributes(source: "corporate_portal", user: user)
    expect(log.old_value["name"]).to eq("Aisha Rahman")
    expect(log.new_value["name"]).to eq("Aisha binti Rahman")
  end

  it "renders one block per guest, plus an empty slot for each unnamed adult" do
    booking = book
    lead = booking.booking_guests.find_by!(is_primary: true)

    get edit_corporate_booking_guests_path(booking)

    doc = response.parsed_body
    expect(doc.at_css("input[name='guests[#{lead.id}][name]']")["value"]).to eq("Aisha Rahman")
    expect(doc.at_css("[name='guests[#{lead.id}][country]']")).to be_present
    expect(doc.at_css("input[name='guests[new0][name]']")).to be_present
    expect(doc.at_css("input[name='guests[#{lead.id}][government_id]']")["value"]).to be_blank
  end

  it "adds a companion the agent did not know at booking time" do
    booking = book

    expect {
      patch corporate_booking_guests_path(booking), params: {
        guests: { "new0" => { name: "Farid Rahman", country: "Singapore", government_id: "K7654321", date_of_birth: "1988-01-01" } }
      }
    }.to change { booking.booking_guests.count }.by(1)

    expect(BookingAuditLog.where(auditable: booking, action_type: "guest_added", source: "corporate_portal")).to exist
  end

  it "records nothing when the agent saves without changing anything" do
    booking = book
    lead = booking.booking_guests.find_by!(is_primary: true)

    patch corporate_booking_guests_path(booking), params: {
      guests: { lead.id.to_s => { name: "Aisha Rahman", phone: "+60123456789", email: "aisha@example.com",
                                  country: "Singapore", government_id: "", date_of_birth: "1990-04-02" } }
    }

    expect(BookingAuditLog.where(auditable: booking, action_type: "guest_updated")).to be_empty
  end

  it "stops editing once the guest has checked in" do
    booking = book
    booking.update_columns(status: "checked_in")

    get edit_corporate_booking_guests_path(booking)

    expect(response).to redirect_to(corporate_booking_path(booking))
    get corporate_booking_path(booking)
    expect(response.body).not_to include("Edit guests")
  end

  it "does not find another agency's booking" do
    other = create(:booking, hotel: hotel, hotel_corporate_account: create(:hotel_corporate_account, hotel: hotel))

    get edit_corporate_booking_guests_path(other)

    expect(response).to have_http_status(:not_found)
  end
end
