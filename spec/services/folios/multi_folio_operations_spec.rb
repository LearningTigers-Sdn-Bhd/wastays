# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Multi-folio operations" do
  around { |example| travel_to(Time.zone.local(2026, 6, 18, 10, 0, 0)) { example.run } }

  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", currency: "MYR") }
  let(:user) { create(:user, :superadmin) }
  let!(:guest_folio) { create(:booking_folio, hotel: hotel, booking: booking, folio_number: 101, name: "Guest Folio") }
  let!(:company_folio) { create(:booking_folio, :secondary, hotel: hotel, booking: booking, folio_number: 102, name: "Company Folio") }

  describe Folios::CreateFolio do
    it "creates a non-primary folio and records an operation log" do
      expect {
        @result = described_class.call(booking: booking, user: user, attributes: { name: "Incidentals", folio_type: "external", payer_type: "guest" })
      }.to change(BookingFolio, :count).by(1).and change(FolioOperationLog, :count).by(1)

      expect(@result).to be_success
      expect(@result.folio).not_to be_is_primary
      expect(@result.folio.name).to eq("Incidentals")
      expect(@result.folio.folio_sequence).to eq(3)
      expect(@result.folio.folio_reference_display).to eq("#{booking.reload.folio_account_reference_display}/3")
      expect(FolioOperationLog.last.operation_type).to eq("create_folio")
    end

    it "defaults new folios to external company payer" do
      result = described_class.call(booking: booking, user: user, attributes: {})

      expect(result).to be_success
      expect(result.folio.name).to eq("External Folio")
      expect(result.folio.folio_type).to eq("external")
      expect(result.folio.payer_type).to eq("company")
    end

    it "coerces locked guest and house payer types" do
      guest_result = described_class.call(booking: booking, user: user, attributes: { folio_type: "guest", payer_type: "company" })
      house_result = described_class.call(booking: booking, user: user, attributes: { folio_type: "house", payer_type: "custom" })

      expect(guest_result).to be_success
      expect(guest_result.folio.payer_type).to eq("guest")
      expect(house_result).to be_success
      expect(house_result.folio.payer_type).to eq("hotel")
    end

    it "does not change references when a new folio becomes primary" do
      original_account_reference = booking.reload.folio_account_reference_display
      original_guest_reference = guest_folio.reload.folio_reference_display

      result = described_class.call(
        booking: booking,
        user: user,
        attributes: {
          name: "Company Primary",
          folio_type: "external",
          payer_type: "company",
          is_primary: "1",
          set_folio_as_primary_reason: "Company pays"
        }
      )

      expect(result).to be_success
      expect(booking.reload.folio_account_reference_display).to eq(original_account_reference)
      expect(guest_folio.reload.folio_reference_display).to eq(original_guest_reference)
      expect(result.folio.reload).to be_is_primary
      expect(result.folio.folio_reference_display).to eq("#{original_account_reference}/3")
    end
  end

  describe Folios::RenameFolio do
    it "renames open folios and records an operation log" do
      result = described_class.call(folio: company_folio, user: user, name: "ABC Sdn Bhd", reason: "Company billing")

      expect(result).to be_success
      expect(company_folio.reload.name).to eq("ABC Sdn Bhd")
      expect(FolioOperationLog.last).to have_attributes(operation_type: "rename_folio", reason: "Company billing")
    end
  end

  describe Folios::UpdateFolio do
    it "coerces locked payer types and logs the normalized values" do
      result = described_class.call(
        folio: company_folio,
        user: user,
        attributes: {
          folio_type: "house",
          payer_type: "company",
          reason: "House use"
        }
      )

      expect(result).to be_success
      expect(company_folio.reload).to be_folio_type_house
      expect(company_folio.payer_type).to eq("hotel")
      expect(FolioOperationLog.last.metadata.dig("changes", "payer_type", "to")).to eq("hotel")
    end
  end

  describe Folios::MoveForecast do
    it "moves an active forecast to another open folio" do
      forecast = create(:folio_forecasted_charge, booking_folio: guest_folio, amount: 370, stay_date: Date.current)

      result = described_class.call(forecast: forecast, target_folio: company_folio, user: user, reason: "Company pays room")

      expect(result).to be_success
      expect(forecast.reload.booking_folio).to eq(company_folio)
      expect(FolioOperationLog.last.operation_type).to eq("move_forecast")
    end
  end

  describe Folios::MoveTransaction do
    it "reverses a posted charge and reposts it on the target folio with lineage" do
      charge = create(:folio_transaction, booking_folio: guest_folio, transaction_type: "charge", category: "accommodation", amount: 740, description: "Room Charge")

      expect {
        @result = described_class.call(transaction: charge, target_folio: company_folio, user: user, reason: "Company pays room")
      }.to change(FolioTransaction, :count).by(2).and change(FolioOperationLog, :count).by(1)

      expect(@result).to be_success
      moved = @result.transaction
      expect(charge.reload.voided_by_transaction).to be_present
      expect(moved.booking_folio).to eq(company_folio)
      expect(moved.moved_from_transaction).to eq(charge)
      expect(moved.transfer_group_id).to be_present
      expect(FolioOperationLog.last.operation_type).to eq("move_transaction")
    end

    it "moves generated tax children with the parent charge" do
      parent = create(:folio_transaction, booking_folio: guest_folio, transaction_type: "charge", category: "accommodation", amount: 740, description: "Room Charge")
      tax = create(:folio_transaction, booking_folio: guest_folio, transaction_type: "charge", category: "tax", amount: 59.20, description: "SST", metadata: { parent_folio_transaction_id: parent.id, tax_line: { type: "sst" } })

      result = described_class.call(transaction: parent, target_folio: company_folio, user: user, reason: "Company pays room")

      expect(result).to be_success
      moved_parent, moved_tax = result.transactions
      expect(parent.reload.voided_by_transaction).to be_present
      expect(tax.reload.voided_by_transaction).to be_present
      expect(moved_parent.booking_folio).to eq(company_folio)
      expect(moved_tax.booking_folio).to eq(company_folio)
      expect(moved_tax.metadata["parent_folio_transaction_id"]).to eq(moved_parent.id)
    end
  end

  describe Folios::SplitTransaction do
    it "splits a posted charge between source and target folios" do
      charge = create(:folio_transaction, booking_folio: guest_folio, transaction_type: "charge", category: "accommodation", amount: 740, description: "Room Charge")

      result = described_class.call(transaction: charge, target_folio: company_folio, user: user, reason: "Split company responsibility", percent: 50)

      expect(result).to be_success
      expect(charge.reload.voided_by_transaction).to be_present
      expect(result.source_transactions.first.amount).to eq(370.to_d)
      expect(result.target_transactions.first.amount).to eq(370.to_d)
      expect(result.target_transactions.first.split_from_transaction).to eq(charge)
      expect(FolioOperationLog.last.operation_type).to eq("split_transaction")
    end

    it "splits generated tax children proportionally" do
      parent = create(:folio_transaction, booking_folio: guest_folio, transaction_type: "charge", category: "accommodation", amount: 740, description: "Room Charge")
      create(:folio_transaction, booking_folio: guest_folio, transaction_type: "charge", category: "tax", amount: 59.20, description: "SST", metadata: { parent_folio_transaction_id: parent.id, tax_line: { type: "sst" } })

      result = described_class.call(transaction: parent, target_folio: company_folio, user: user, reason: "Split company responsibility", amount: 370)

      expect(result).to be_success
      source_tax = result.source_transactions.second
      target_tax = result.target_transactions.second
      expect(source_tax.amount).to eq(29.60.to_d)
      expect(target_tax.amount).to eq(29.60.to_d)
      expect(source_tax.metadata["parent_folio_transaction_id"]).to eq(result.source_transactions.first.id)
      expect(target_tax.metadata["parent_folio_transaction_id"]).to eq(result.target_transactions.first.id)
    end
  end

  describe Folios::BookingCheckoutReadiness do
    it "blocks checkout when any folio has a non-zero projected balance" do
      create(:folio_transaction, booking_folio: company_folio, transaction_type: "charge", category: "accommodation", amount: 100)

      result = described_class.call(booking: booking, hotel: hotel)

      expect(result).not_to be_ready
      expect(result.projected_balance).to eq(100.to_d)
      expect(result.blockers.join).to include("Company Folio")
    end
  end
end
