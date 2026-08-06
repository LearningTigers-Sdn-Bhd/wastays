# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::StartPreparation do
  let(:hotel) { create(:hotel, :without_current_business_date) }
  let(:business_date) { Date.current }

  before { BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date) }

  it "creates and then reuses the preparation anchor on first mutation" do
    first = described_class.call(hotel: hotel, business_date: business_date).night_audit
    second = described_class.call(hotel: hotel, business_date: business_date).night_audit

    expect(first).to be_preparing
    expect(second.id).to eq(first.id)
    expect(hotel.current_business_date_record).to be_open
  end
end
