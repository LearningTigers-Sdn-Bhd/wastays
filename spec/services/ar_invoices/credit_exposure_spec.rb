# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArInvoices::CreditExposure do
  it "does not warn below 90 percent of the credit limit" do
    relationship = create(:hotel_corporate_account, :direct_bill, credit_limit: 1000)
    create_invoice(relationship: relationship, amount: 700)

    result = described_class.call(hotel_corporate_account: relationship, pending_amount: 199)

    expect(result.warning_state).to eq("none")
    expect(result.warning?).to eq(false)
    expect(result.projected_exposure).to eq(899.to_d)
  end

  it "warns at 90 percent of the credit limit without blocking" do
    relationship = create(:hotel_corporate_account, :direct_bill, credit_limit: 1000)
    create_invoice(relationship: relationship, amount: 800)

    result = described_class.call(hotel_corporate_account: relationship, pending_amount: 100)

    expect(result.warning_state).to eq("near_limit")
    expect(result.warning_message).to include("90% of credit limit")
    expect(result.warning_message).to include("Direct Bill is still allowed")
  end

  it "warns when projected exposure exceeds the credit limit" do
    relationship = create(:hotel_corporate_account, :direct_bill, credit_limit: 1000)
    create_invoice(relationship: relationship, amount: 900)

    result = described_class.call(hotel_corporate_account: relationship, pending_amount: 101)

    expect(result.warning_state).to eq("over_limit")
    expect(result.warning_message).to include("exceeds credit limit")
    expect(result.warning_message).to include("An authorized override is required")
  end

  it "warns when no credit limit is set" do
    relationship = create(:hotel_corporate_account, :direct_bill, credit_limit: nil)

    result = described_class.call(hotel_corporate_account: relationship, pending_amount: 100)

    expect(result.warning_state).to eq("no_limit")
    expect(result.warning_message).to include("No credit limit is set")
  end

  it "flags outstanding invoices outside the account credit currency as non-comparable" do
    relationship = create(:hotel_corporate_account, credit_limit: 1_000, credit_currency: "MYR")
    create_invoice(relationship: relationship, amount: 700)
    create_invoice(relationship: relationship, amount: 600, currency: "USD")

    result = described_class.call(hotel_corporate_account: relationship)

    expect(result.current_outstanding).to eq(700.to_d)
    expect(result.warning_state).to eq("currency_mismatch")
    expect(result.non_comparable_currencies).to eq([ "USD" ])
    expect(result).to be_requires_override
  end

  it "requires an override for a pending balance in another currency" do
    relationship = create(:hotel_corporate_account, credit_limit: 1_000, credit_currency: "MYR")
    create_invoice(relationship: relationship, amount: 800)

    result = described_class.call(
      hotel_corporate_account: relationship,
      pending_amount: 500,
      pending_currency: "USD"
    )

    expect(result.pending_amount).to eq(0.to_d)
    expect(result.projected_exposure).to eq(800.to_d)
    expect(result.warning_state).to eq("currency_mismatch")
    expect(result.non_comparable_currencies).to eq([ "USD" ])
    expect(result).to be_requires_override
  end

  it "retains the amount behind each non-comparable currency" do
    relationship = create(:hotel_corporate_account, credit_limit: 1_000, credit_currency: "MYR")
    create_invoice(relationship: relationship, amount: 700)
    create_invoice(relationship: relationship, amount: 600, currency: "USD")
    create_invoice(relationship: relationship, amount: 40, currency: "SGD")

    result = described_class.call(hotel_corporate_account: relationship)

    expect(result.non_comparable_totals).to eq("USD" => 600.to_d, "SGD" => 40.to_d)
    expect(result.non_comparable_currencies).to eq([ "SGD", "USD" ])
  end

  describe ".for_relationships" do
    it "returns the same results as the single-record path" do
      hotel = create(:hotel)
      with_balance = create(:hotel_corporate_account, hotel: hotel, credit_limit: 1_000, credit_currency: "MYR")
      foreign_only = create(:hotel_corporate_account, hotel: hotel, credit_limit: 1_000, credit_currency: "MYR")
      empty = create(:hotel_corporate_account, hotel: hotel, credit_limit: 1_000, credit_currency: "MYR")

      create_invoice(relationship: with_balance, amount: 950)
      create_invoice(relationship: foreign_only, amount: 800, currency: "USD")

      results = described_class.for_relationships([ with_balance, foreign_only, empty ])

      expect(results[with_balance].projected_exposure).to eq(950.to_d)
      expect(results[with_balance].warning_state).to eq("near_limit")

      # The whole point of the fix: a MYR-zero account with open USD AR must not read as clean.
      expect(results[foreign_only].current_outstanding).to eq(0.to_d)
      expect(results[foreign_only].non_comparable_totals).to eq("USD" => 800.to_d)
      expect(results[foreign_only]).to be_requires_override

      expect(results[empty].current_outstanding).to eq(0.to_d)
      expect(results[empty].warning_state).to eq("none")
    end

    it "resolves every relationship with one receivables query" do
      hotel = create(:hotel)
      relationships = create_list(:hotel_corporate_account, 5, hotel: hotel, credit_limit: 1_000)
      relationships.each { |relationship| create_invoice(relationship: relationship, amount: 100) }

      queries = count_queries { described_class.for_relationships(relationships) }

      # Receivable is backed by the ar_invoices table.
      expect(queries.grep(/FROM "ar_invoices"/).size).to eq(1)
    end

    it "returns an empty hash without querying for an empty collection" do
      expect(described_class.for_relationships([])).to eq({})
    end
  end

  def count_queries(&block)
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      queries << payload[:sql] unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ])
    end
    block.call
    queries
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  def create_invoice(relationship:, amount:, currency: "MYR")
    booking = create(:booking, hotel: relationship.hotel, currency: currency)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: relationship.hotel, hotel_corporate_account: relationship, currency: currency)
    create(:ar_invoice, hotel: relationship.hotel, booking_folio: folio, hotel_corporate_account: relationship, amount: amount, outstanding_amount: amount, currency: currency)
  end
end
