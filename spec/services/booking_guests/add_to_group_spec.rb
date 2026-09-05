# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingGuests::AddToGroup do
  let(:group) { create(:group_booking) }
  let!(:booking_one) { create(:booking, hotel: group.hotel, group_booking: group, group_position: 1, status: "confirmed") }
  let!(:booking_two) { create(:booking, hotel: group.hotel, group_booking: group, group_position: 2, status: "checked_in") }
  let(:actor) { create(:user, account: group.hotel.account) }
  let(:attributes) { { name: "Shared Guest", country: "Malaysia", document_type: "passport", date_of_birth: "1990-01-01" } }

  it "creates one reusable guest and attaches it as an additional payer to every child" do
    result = described_class.call(group_booking: group, attributes:, actor:)

    expect(result).to be_success
    expect(result.booking_guests.map(&:guest_id).uniq).to contain_exactly(result.guest.id)
    expect(result.booking_guests.map(&:booking_id)).to contain_exactly(booking_one.id, booking_two.id)
    expect(result.booking_guests).to all(satisfy { |booking_guest| !booking_guest.primary? })
    expect(BookingBillingParty.guests.where(booking_id: [ booking_one.id, booking_two.id ], booking_guest_id: result.booking_guests.map(&:id)).count).to eq(2)
    expect(BookingAuditLog.where(auditable: [ booking_one, booking_two ], action_type: "guest_added").count).to eq(2)
  end

  it "rolls back every child when one booking is ineligible" do
    booking_two.update_column(:status, "cancelled")

    expect do
      result = described_class.call(group_booking: group, attributes:, actor:)
      expect(result).not_to be_success
    end.not_to change(Guest, :count)

    expect(booking_one.booking_guests).to be_empty
    expect(booking_two.booking_guests).to be_empty
  end
  it "links a picked guest to every child and leaves the record alone" do
    existing = create(:guest, name: "Repeat Guest", phone: "+60111111111")

    result = described_class.call(
      group_booking: group, attributes: attributes.merge(name: "Repeat Guest", phone: "+60122222222"),
      actor:, existing_guest: existing
    )

    expect(result).to be_success
    expect(result.guest.id).to eq(existing.id)
    expect(result.booking_guests.map(&:phone_snapshot).uniq).to eq([ "+60122222222" ])
    expect(existing.reload.phone).to eq("+60111111111")
  end

  it "writes the typed values to the record when the profile update is asked for" do
    existing = create(:guest, name: "Repeat Guest", phone: "+60111111111")

    described_class.call(
      group_booking: group, attributes: attributes.merge(name: "Repeat Guest", phone: "+60122222222"),
      actor:, existing_guest: existing, update_profile: true
    )

    expect(existing.reload.phone).to eq("+60122222222")
  end
end
