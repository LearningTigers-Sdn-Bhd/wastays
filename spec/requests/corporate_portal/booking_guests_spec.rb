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
  describe "boat transfers" do
    before do
      hotel.update!(allow_boat_information: true)
      create(:hotel_boat_schedule, hotel: hotel, kind: "boat_in", time: "09:00")
      create(:hotel_boat_schedule, hotel: hotel, kind: "boat_in", time: "14:00")
      create(:hotel_boat_schedule, hotel: hotel, kind: "boat_out", time: "10:00")
      create(:hotel_boat_schedule, :archived, hotel: hotel, kind: "boat_in", time: "07:00")
    end

    def book_with(boat)
      post corporate_bookings_path, params: {
        hotel_relationship_id: relationship.id,
        booking: {
          room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
          adults: 2, children: 0, rooms: 1, **boat,
          rooms_detail: { "0" => { guests: { "0" => { name: "Aisha Rahman", phone: "+60123456789", country: "Singapore",
                                                       government_id: "K1234567", date_of_birth: "1990-04-02" } } } }
        }
      }
    end

    def lead_of(booking) = booking.booking_guests.find_by!(is_primary: true)
    def local_time(booking, value) = Boats::Schedule.time_of_day(hotel: hotel, timestamp: value)

    it "lets the agent pick boats when booking, landing on the stay's own dates" do
      book_with(boat_in_time: "14:00", boat_out_time: "10:00")

      booking = Booking.order(:id).last
      lead = lead_of(booking)
      expect(local_time(booking, lead.boat_in_at)).to eq("14:00")
      expect(lead.boat_in_at.in_time_zone(hotel.hotel_time_zone).to_date).to eq(check_in)
      expect(local_time(booking, lead.boat_out_at)).to eq("10:00")
      expect(lead.boat_out_at.in_time_zone(hotel.hotel_time_zone).to_date).to eq(check_out)
    end

    it "refuses a slot the hotel doesn't run, including a retired one" do
      expect { book_with(boat_in_time: "07:00") }.not_to change(Booking, :count)

      expect(flash[:alert]).to include("Choose a boat-in time from the hotel's boat timetable.")
    end

    it "shows the boat fields only on a hotel with a boat timetable" do
      get new_corporate_booking_path(hotel_relationship_id: relationship.id, check_in: check_in, check_out: check_out,
                                     adults: 2, rooms: 1, room_type_id: room_type.id)
      expect(response.parsed_body.at_css("select[name='booking[boat_in_time]']")).to be_present

      hotel.update!(allow_boat_information: false)
      get new_corporate_booking_path(hotel_relationship_id: relationship.id, check_in: check_in, check_out: check_out,
                                     adults: 2, rooms: 1, room_type_id: room_type.id)
      expect(response.parsed_body.at_css("select[name='booking[boat_in_time]']")).to be_nil
    end

    it "flags missing boat times on the booking and lets the agent add them before arrival, audited" do
      book_with({})
      booking = Booking.order(:id).last

      get corporate_booking_path(booking)
      card = response.parsed_body.at_css('[data-testid="agent-room-detail"]').text.squish
      expect(card).to include("Boat-in not added yet", "Boat-out not added yet", "Add boat times")

      get edit_corporate_booking_guests_path(booking)
      expect(response.parsed_body.at_css("select[name='boat_in_time']")).to be_present

      patch corporate_booking_guests_path(booking), params: { guests: {}, boat_in_time: "09:00", boat_out_time: "10:00" }

      expect(response).to redirect_to(corporate_booking_path(booking))
      lead = lead_of(booking)
      expect(local_time(booking, lead.boat_in_at)).to eq("09:00")
      expect(local_time(booking, lead.boat_out_at)).to eq("10:00")
      log = BookingAuditLog.where(auditable: booking, action_type: "guest_updated", source: "corporate_portal").sole
      expect(log.old_value["boat_in_at"]).to be_nil
      expect(log.new_value["boat_in_at"]).to be_present

      get corporate_booking_path(booking)
      expect(response.body).not_to include("not added yet")
    end

    it "records nothing when the boat times did not change" do
      book_with(boat_in_time: "09:00", boat_out_time: "10:00")
      booking = Booking.order(:id).last

      patch corporate_booking_guests_path(booking), params: { guests: {}, boat_in_time: "09:00", boat_out_time: "10:00" }

      expect(response).to redirect_to(corporate_booking_path(booking))
      expect(BookingAuditLog.where(auditable: booking, action_type: "guest_updated")).to be_empty
    end

    it "refuses a boat slot the hotel doesn't run when editing" do
      book_with({})
      booking = Booking.order(:id).last

      patch corporate_booking_guests_path(booking), params: { guests: {}, boat_out_time: "23:00" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Choose a boat-out time from the hotel&#39;s boat timetable.")
      expect(lead_of(booking).boat_out_at).to be_nil
    end
  end
end
