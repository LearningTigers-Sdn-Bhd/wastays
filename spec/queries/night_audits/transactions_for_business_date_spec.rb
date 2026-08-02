# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::TransactionsForBusinessDate do
  let(:hotel) { create(:hotel) }
  let(:business_date) { Date.new(2026, 5, 20) }

  it "returns a relation containing only the hotel's transactions posted to the business date" do
    matching = create_transaction(hotel:, posting_date: business_date)
    create_transaction(hotel:, posting_date: business_date + 1.day)
    create_transaction(hotel: create(:hotel), posting_date: business_date)

    result = described_class.call(hotel:, business_date: business_date.to_time)

    expect(result).to be_an(ActiveRecord::Relation)
    expect(result).to contain_exactly(matching)
  end

  it "uses posting_date regardless of when the transaction was created" do
    window = hotel.business_day_window_for(business_date)
    historical_correction = create_transaction(
      hotel:,
      posting_date: business_date,
      created_at: window.end + 1.day
    )
    create_transaction(
      hotel:,
      posting_date: business_date + 1.day,
      created_at: window.begin + 1.hour
    )

    expect(described_class.call(hotel:, business_date:)).to contain_exactly(historical_correction)
  end

  def create_transaction(hotel:, posting_date:, created_at: Time.current)
    booking = create(:booking, hotel:)
    folio = create(:booking_folio, booking:)
    create(:folio_transaction, booking_folio: folio, posting_date:, created_at:)
  end
end
