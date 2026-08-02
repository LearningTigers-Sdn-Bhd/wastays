require "rails_helper"

RSpec.describe NightAudits::Resolutions::ValidateContext do
  it "rejects an unauthorized actor before evaluating blockers" do
    hotel = create(:hotel)
    booking = create(:booking, hotel: hotel)
    audit = create(:night_audit, hotel: hotel, status: "blocked")
    actor = instance_double(User, superadmin?: false, has_permission?: false)

    expect(described_class.call(
      night_audit: audit,
      booking: booking,
      actor: actor,
      business_date_record: nil,
      blocker_booking_ids: -> { raise "not evaluated" },
      blocker_name: "missing folio",
      permission: "manage_night_audit"
    )).to eq("You do not have permission to resolve Night Audit blockers.")
  end
end
