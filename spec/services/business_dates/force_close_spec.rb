# frozen_string_literal: true

require "rails_helper"

RSpec.describe BusinessDates::ForceClose do
  it "delegates to atomic close-and-open-next force mode" do
    hotel = create(:hotel)
    actor = create(:user, :superadmin)
    hotel.current_business_date_record.update!(status: "audit_blocked")

    result = described_class.call!(hotel: hotel, actor: actor, reason: "Approved exception")

    expect(result.closed_business_date).to be_force_closed
    expect(result.next_business_date).to be_open
  end
end
