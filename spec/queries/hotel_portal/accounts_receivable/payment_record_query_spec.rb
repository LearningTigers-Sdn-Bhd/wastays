# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::AccountsReceivable::PaymentRecordQuery do
  let(:hotel) { create(:hotel) }
  let(:relationship) { create(:hotel_corporate_account, hotel:) }

  it "counts both sources and returns only the locator candidates for the requested page" do
    Array.new(30) do |index|
      create(:ar_payment, hotel:, hotel_corporate_account: relationship, received_at: Date.new(2026, 6, 1) + index.days)
    end
    Array.new(10) do |index|
      create(:ar_payment_submission, hotel:, hotel_corporate_account: relationship, created_at: Time.zone.local(2026, 7, index + 1))
    end

    result = query.call(page: 2, limit: 25)

    expect(result.count).to eq(40)
    expect(result.locators.size).to eq(40)
    expect(result.locators).to eq(result.locators.sort_by { |locator| [ -locator.sort_time.to_f, described_class::SOURCE_ORDER.fetch(locator.source_type), -locator.source_id ] })
  end

  it "uses submissions before payments for equal timestamps" do
    time = Time.zone.local(2026, 6, 18)
    payment = create(:ar_payment, hotel:, hotel_corporate_account: relationship, received_at: time.to_date)
    submission = create(:ar_payment_submission, hotel:, hotel_corporate_account: relationship, created_at: time)

    result = query.call(page: 1, limit: 25)

    expect(result.locators.map { |locator| [ locator.source_type, locator.source_id ] }).to eq(
      [ [ :submission, submission.id ], [ :payment, payment.id ] ]
    )
  end

  it "preserves status, search, date, account, and hotel filters" do
    pending = create(:ar_payment_submission, hotel:, hotel_corporate_account: relationship, reference_number: "MATCH", received_at: Date.new(2026, 6, 18))
    create(:ar_payment, hotel:, hotel_corporate_account: relationship, reference_number: "MATCH", received_at: Date.new(2026, 6, 18))
    other_hotel = create(:hotel)
    other_relationship = create(:hotel_corporate_account, hotel: other_hotel)
    create(:ar_payment_submission, hotel: other_hotel, hotel_corporate_account: other_relationship, reference_number: "MATCH", received_at: Date.new(2026, 6, 18))

    result = described_class.new(
      hotel:,
      query: "MATCH",
      status: "pending",
      hotel_corporate_account_id: relationship.id,
      received_from: Date.new(2026, 6, 18),
      received_to: Date.new(2026, 6, 18)
    ).call(page: 1, limit: 25)

    expect(result.count).to eq(1)
    expect(result.locators.map(&:source_id)).to eq([ pending.id ])
  end

  private

  def query
    described_class.new(
      hotel:,
      query: "",
      status: nil,
      hotel_corporate_account_id: nil,
      received_from: nil,
      received_to: nil
    )
  end
end
