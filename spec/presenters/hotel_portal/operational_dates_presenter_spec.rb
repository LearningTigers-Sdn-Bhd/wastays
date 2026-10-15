# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::OperationalDatesPresenter do
  let(:hotel) do
    create(
      :hotel,
      :without_current_business_date,
      status: "live",
      time_zone: "Kuala Lumpur"
    )
  end

  it "presents the persisted Working Date and hotel-local System Date" do
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.new(2026, 9, 14))
    presenter = described_class.new(hotel: hotel, now: Time.utc(2026, 9, 14, 16, 30))

    expect(presenter.as_json).to eq(
      working_date: { value: "2026-09-14", label: "14 Sep 2026" },
      system_date: { value: "2026-09-15", label: "15 Sep 2026" }
    )
  end

  it "reports an unavailable Working Date without creating one" do
    presenter = described_class.new(hotel: hotel, now: Time.utc(2026, 9, 14, 16, 30))

    expect { presenter.as_json }.not_to change(HotelBusinessDate, :count)
    expect(presenter.as_json).to include(
      working_date: { value: nil, label: "Unavailable" }
    )
  end
end
