require "rails_helper"

RSpec.describe Public::Concierge::CheckInPresenter do
  let(:hotel) { create(:hotel, status: "live") }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:booking) do
    create(:booking, hotel: hotel, guest_name: "Hanami Sato",
      check_in: Date.new(2026, 9, 22), check_out: Date.new(2026, 9, 24))
  end

  subject(:presenter) { described_class.new(booking: booking, hotel: hotel) }

  it "describes the booking for the summary cards" do
    booking.booking_rooms.create!(room_type: room_type, subtotal: 200, room_type_snapshot: { "name" => "Deluxe King" })

    expect(presenter.guest_name).to eq("Hanami Sato")
    expect(presenter.nights).to eq(2)
    expect(presenter.check_in_label).to eq("Tue, 22 Sep")
    expect(presenter.check_out_label).to eq("Thu, 24 Sep")
    expect(presenter.room_type_names).to eq([ "Deluxe King" ])
    expect(presenter.confirmation_code).to eq(booking.confirmation_token.to_s.upcase)
  end

  it "says the details are needed until pre-check-in is complete" do
    expect(presenter.status_label).to eq("Details needed")

    booking.create_pre_checkin!(status: "completed", document_status: "verified",
                                signature_status: "signed", completed_at: Time.current)

    expect(described_class.new(booking: booking.reload, hotel: hotel).status_label).to eq("Details done")
  end
end
