require "rails_helper"

RSpec.describe NightAudits::Evaluation::SerializeItems do
  it "preserves the persisted booking payload contract" do
    booking = create(:booking)

    expect(described_class.new.booking(booking, "Reason")).to include(
      "booking_id" => booking.id,
      "confirmation_token" => booking.confirmation_token,
      "reason" => "Reason"
    )
  end
end
