# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::PostStaffTransaction do
  around { |example| travel_to(Time.zone.local(2026, 6, 10, 3, 0, 0)) { example.run } }

  let(:folio) { create(:booking_folio) }
  let(:user) { create(:user, :superadmin) }

  it "posts a cash payment" do
    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "payment",
      category: "cash",
      amount: "100.00",
      description: "Cash payment",
      options: { payment_source: "cash" }
    )

    expect(result.success?).to be(true)
    transaction = result.transaction
    expect(transaction.transaction_type).to eq("payment")
    expect(transaction.category).to eq("cash")
    expect(transaction.transaction_code.code).to eq("CASH")
    expect(transaction.amount).to eq(100.0)
    expect(transaction.metadata["payment_source"]).to eq("cash")
    expect(transaction.metadata["posting_source"]).to eq("staff")
    expect(transaction.metadata["posted_by_user_id"]).to eq(user.id)
  end

  it "maps staff payment sources to default payment transaction codes" do
    Financials::EnsureDefaultTransactionCodes.call(folio.hotel)

    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "payment",
      category: "cash",
      transaction_code_id: folio.hotel.transaction_codes.find_by!(system_key: "refund").id,
      amount: "100.00",
      description: "Bank transfer",
      options: {
        payment_source: "bank",
        metadata: { reference: "BNK-123", note: "Banked at desk" }
      }
    )

    expect(result.success?).to be(true)
    expect(result.transaction.category).to eq("booking_payment")
    expect(result.transaction.transaction_code.code).to eq("BANK")
    expect(result.transaction.metadata["payment_source"]).to eq("bank")
    expect(result.transaction.metadata["source_references"]).to eq("bank_reference" => "BNK-123")
    expect(result.transaction.metadata["note"]).to eq("Banked at desk")
  end

  it "requires source references for gateway and OTA staff payments" do
    gateway_result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "payment",
      category: "cash",
      amount: "100.00",
      description: "Gateway recovery",
      options: { payment_source: "gateway" }
    )
    ota_result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "payment",
      category: "cash",
      amount: "100.00",
      description: "OTA payment",
      options: { payment_source: "ota" }
    )

    expect(gateway_result.success?).to be(false)
    expect(gateway_result.error).to eq("Gateway Manual Recovery reference is required.")
    expect(ota_result.success?).to be(false)
    expect(ota_result.error).to eq("OTA Collected reference is required.")
  end

  it "posts an other charge" do
    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "charge",
      category: "other",
      amount: "25.00",
      description: "Lost key charge"
    )

    expect(result.success?).to be(true)
    expect(result.transaction.transaction_type).to eq("charge")
    expect(result.transaction.category).to eq("other")
    expect(result.transaction.amount).to eq(25.0)
  end

  it "posts a selected taxable charge code with active linked taxes" do
    hotel = folio.hotel
    active_tax = create(:hotel_tax, hotel: hotel, name: "SST 8%", rate_type: "percentage", amount: 8, enabled: true)
    inactive_tax = create(:hotel_tax, hotel: hotel, name: "Inactive Fee", rate_type: "flat", amount: 5, enabled: false)
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    code = hotel.transaction_codes.find_by!(system_key: "fnb_revenue")
    code.update!(is_taxable: true)
    code.taxes = [ active_tax, inactive_tax ]

    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "charge",
      category: nil,
      transaction_code_id: code.id,
      amount: "50.00",
      description: "Restaurant charge"
    )

    expect(result.success?).to be(true)
    expect(result.transaction.category).to eq("fb")
    expect(result.transaction.transaction_code).to eq(code)
    expect(result.tax_transactions.size).to eq(1)

    tax_transaction = result.tax_transactions.first
    expect(tax_transaction.category).to eq("tax")
    expect(tax_transaction.amount).to eq(4.0)
    expect(tax_transaction.metadata["parent_folio_transaction_id"]).to eq(result.transaction.id)
    expect(tax_transaction.metadata["source_transaction_code_id"]).to eq(code.id)
  end

  it "posts selected active primary taxes for taxable charge codes" do
    hotel = folio.hotel
    hotel.update!(sst_enabled: true, tourism_tax_enabled: true, tourism_tax_amount: 10)
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    code = hotel.transaction_codes.find_by!(system_key: "fnb_revenue")
    code.update!(is_taxable: true)
    code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
    code.transaction_code_taxes.create!(primary_tax_key: "tourism_tax")

    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "charge",
      category: nil,
      transaction_code_id: code.id,
      amount: "50.00",
      description: "Restaurant charge"
    )

    expect(result.success?).to be(true)
    expect(result.tax_transactions.map(&:amount)).to match_array([ 4.to_d, 10.to_d ])
    expect(result.tax_transactions.map { |transaction| transaction.metadata.dig("tax_line", "type") }).to match_array(%w[sst tourism_tax])
    expect(result.tax_transactions.map { |transaction| transaction.transaction_code.system_key }).to match_array(%w[sst_tax tourism_tax])
  end

  it "skips selected inactive primary taxes" do
    hotel = folio.hotel
    hotel.update!(sst_enabled: false, tourism_tax_enabled: true, tourism_tax_amount: 10)
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    code = hotel.transaction_codes.find_by!(system_key: "fnb_revenue")
    code.update!(is_taxable: true)
    code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
    code.transaction_code_taxes.create!(primary_tax_key: "tourism_tax")

    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "charge",
      category: nil,
      transaction_code_id: code.id,
      amount: "50.00",
      description: "Restaurant charge"
    )

    expect(result.success?).to be(true)
    expect(result.tax_transactions.size).to eq(1)
    expect(result.tax_transactions.first.metadata.dig("tax_line", "type")).to eq("tourism_tax")
  end

  it "posts selected default charge code categories" do
    Financials::EnsureDefaultTransactionCodes.call(folio.hotel)
    code = folio.hotel.transaction_codes.find_by!(system_key: "parking_revenue")

    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "charge",
      category: nil,
      transaction_code_id: code.id,
      amount: "12.00",
      description: "Parking charge"
    )

    expect(result.success?).to be(true)
    expect(result.transaction.category).to eq("parking")
    expect(result.transaction.transaction_code).to eq(code)
  end

  it "requires a transaction code for manual charge mode" do
    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "charge",
      category: "other",
      amount: "12.00",
      description: "Parking charge",
      options: { require_transaction_code: true }
    )

    expect(result.success?).to be(false)
    expect(result.error).to eq("Transaction code is required for manual charges.")
  end

  it "rejects inactive transaction codes in manual charge mode" do
    code = create(:transaction_code, hotel: folio.hotel, kind: "charge", category: "fb", active: false)

    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "charge",
      category: nil,
      transaction_code_id: code.id,
      amount: "12.00",
      description: "Restaurant charge",
      options: { require_transaction_code: true }
    )

    expect(result.success?).to be(false)
    expect(result.error).to eq("Transaction code is not available.")
  end

  it "rejects transaction codes from another hotel in manual charge mode" do
    other_hotel_code = create(:transaction_code, kind: "charge", category: "fb")

    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "charge",
      category: nil,
      transaction_code_id: other_hotel_code.id,
      amount: "12.00",
      description: "Restaurant charge",
      options: { require_transaction_code: true }
    )

    expect(result.success?).to be(false)
    expect(result.error).to eq("Transaction code is not available.")
  end

  it "rejects non-charge transaction codes in manual charge mode" do
    code = create(:transaction_code, hotel: folio.hotel, kind: "payment", category: "cash")

    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "charge",
      category: nil,
      transaction_code_id: code.id,
      amount: "12.00",
      description: "Restaurant charge",
      options: { require_transaction_code: true }
    )

    expect(result.success?).to be(false)
    expect(result.error).to eq("Transaction code must be a charge code.")
  end

  it "stores staff reference and note metadata on parent and tax rows" do
    hotel = folio.hotel
    hotel.update!(sst_enabled: true)
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    code = hotel.transaction_codes.find_by!(system_key: "fnb_revenue")
    code.update!(is_taxable: true)
    code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")

    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "charge",
      category: nil,
      transaction_code_id: code.id,
      amount: "50.00",
      description: "Restaurant charge",
      options: {
        require_transaction_code: true,
        metadata: {
          reference: "MGR-123",
          note: "Approved by manager"
        }
      }
    )

    expect(result.success?).to be(true)
    expect(result.transaction.metadata["reference"]).to eq("MGR-123")
    expect(result.transaction.metadata["note"]).to eq("Approved by manager")
    expect(result.tax_transactions.first.metadata["reference"]).to eq("MGR-123")
    expect(result.tax_transactions.first.metadata["note"]).to eq("Approved by manager")
  end

  it "rolls back the parent transaction if generated tax posting fails" do
    hotel = folio.hotel
    hotel.update!(sst_enabled: true)
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    code = hotel.transaction_codes.find_by!(system_key: "fnb_revenue")
    code.update!(is_taxable: true)
    code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")

    allow(Folios::InsertTransaction).to receive(:new).and_wrap_original do |method, **kwargs|
      if kwargs[:category] == "tax"
        instance_double(Folios::InsertTransaction, call: OpenStruct.new(success?: false, error: "tax failed"))
      else
        method.call(**kwargs)
      end
    end

    expect {
      @result = described_class.call(
        folio: folio,
        user: user,
        transaction_type: "charge",
        category: nil,
        transaction_code_id: code.id,
        amount: "50.00",
        description: "Restaurant charge",
        options: { require_transaction_code: true }
      )
    }.not_to change(FolioTransaction, :count)

    expect(@result.success?).to be(false)
    expect(@result.error).to eq("tax failed")
  end

  it "does not post tax transactions for non-taxable selected charge codes" do
    code = create(:transaction_code, hotel: folio.hotel, kind: "charge", category: "fb", is_taxable: false)
    code.taxes = [ create(:hotel_tax, hotel: folio.hotel, rate_type: "percentage", amount: 8) ]

    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "charge",
      category: nil,
      transaction_code_id: code.id,
      amount: "50.00",
      description: "Restaurant charge"
    )

    expect(result.success?).to be(true)
    expect(result.tax_transactions).to be_nil
    expect(folio.folio_transactions.where(category: "tax")).to be_empty
  end

  it "posts an adjustment" do
    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "adjustment",
      category: "write_off",
      amount: "-10.00",
      description: "Write off balance"
    )

    expect(result.success?).to be(true)
    expect(result.transaction.transaction_type).to eq("adjustment")
    expect(result.transaction.category).to eq("write_off")
    expect(result.transaction.amount).to eq(-10.0)
  end

  it "records refunds as negative payments" do
    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "payment",
      category: "refund",
      amount: "50.00",
      description: "Refund credit balance"
    )

    expect(result.success?).to be(true)
    expect(result.transaction.transaction_type).to eq("payment")
    expect(result.transaction.category).to eq("refund")
    expect(result.transaction.amount).to eq(-50.0)
  end

  it "rejects manual accommodation charges" do
    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "charge",
      category: "accommodation",
      amount: "100.00",
      description: "Manual room charge"
    )

    expect(result.success?).to be(false)
    expect(result.error).to eq("Category is not allowed for charge transactions.")
  end

  it "posts gateway manual recovery only through the mapped payment source" do
    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "payment",
      category: "gateway_payment",
      amount: "100.00",
      description: "Gateway payment",
      options: { payment_source: "gateway", metadata: { reference: "cap_123" } }
    )

    expect(result.success?).to be(true)
    expect(result.transaction.category).to eq("gateway_payment")
    expect(result.transaction.transaction_code.code).to eq("GATEWAY")
    expect(result.transaction.metadata["source_references"]).to eq("gateway_reference" => "cap_123")
  end

  it "rejects blank descriptions" do
    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "payment",
      category: "cash",
      amount: "100.00",
      description: "",
      options: { payment_source: "cash" }
    )

    expect(result.success?).to be(false)
    expect(result.error).to eq("Description can't be blank.")
  end

  it "rejects negative cash payment amounts" do
    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "payment",
      category: "cash",
      amount: "-100.00",
      description: "Cash payment",
      options: { payment_source: "cash" }
    )

    expect(result.success?).to be(false)
    expect(result.error).to eq("Amount must be greater than zero.")
  end

  it "rejects negative charge amounts" do
    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "charge",
      category: "other",
      amount: "-25.00",
      description: "Other charge"
    )

    expect(result.success?).to be(false)
    expect(result.error).to eq("Amount must be greater than zero.")
  end

  it "rejects zero adjustment amounts" do
    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "adjustment",
      category: "adjustment",
      amount: "0.00",
      description: "No-op adjustment"
    )

    expect(result.success?).to be(false)
    expect(result.error).to eq("Amount can't be zero.")
  end
end
