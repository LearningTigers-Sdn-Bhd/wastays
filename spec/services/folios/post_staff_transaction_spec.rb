# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::PostStaffTransaction do
  around { |example| travel_to(Time.zone.local(2026, 6, 10, 3, 0, 0)) { example.run } }

  let(:folio) { create(:booking_folio) }
  let(:user) { create(:user, :superadmin) }

  def grant_permission(user, slug, hotel)
    permission = Permission.find_by(slug: slug) || create(:permission, slug: slug, name: slug.tr("_", " ").titleize)
    access = user.user_hotel_accesses.find_by(hotel: hotel)
    role = access&.role || create(:role, account: hotel.account)
    create(:role_permission, role: role, permission: permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: role) if access.blank?
  end

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

  it "routes a manual charge by the selected transaction code rule" do
    hotel = folio.hotel
    booking = folio.booking
    company_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel)
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    code = hotel.transaction_codes.find_by!(system_key: "fnb_revenue")
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: code, target_folio: company_folio)

    result = described_class.call(
      folio: company_folio,
      user: user,
      transaction_type: "charge",
      category: nil,
      transaction_code_id: code.id,
      amount: "50.00",
      description: "Restaurant charge",
      options: { require_transaction_code: true }
    )

    expect(result.success?).to be(true)
    expect(result.transaction.booking_folio).to eq(company_folio)
    expect(result.transaction.metadata["route_source"]).to eq("routing_rule")
  end

  it "requires permission and reason when selected folio overrides routing" do
    hotel = folio.hotel
    booking = folio.booking
    company_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel)
    staff_user = create(:user, account: hotel.account)
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    code = hotel.transaction_codes.find_by!(system_key: "fnb_revenue")
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: code, target_folio: company_folio)

    no_reason = described_class.call(
      folio: folio,
      user: staff_user,
      transaction_type: "charge",
      category: nil,
      transaction_code_id: code.id,
      amount: "50.00",
      description: "Restaurant charge",
      options: { require_transaction_code: true }
    )
    expect(no_reason.success?).to be(false)
    expect(no_reason.error).to eq("Override reason can't be blank.")

    no_permission = described_class.call(
      folio: folio,
      user: staff_user,
      transaction_type: "charge",
      category: nil,
      transaction_code_id: code.id,
      amount: "50.00",
      description: "Restaurant charge",
      options: { require_transaction_code: true, routing_override_reason: "Guest pays this one" }
    )
    expect(no_permission.success?).to be(false)
    expect(no_permission.error).to eq("You do not have permission to override folio routing.")

    grant_permission(staff_user, "manage_folio_movements", hotel)
    grant_permission(staff_user, "post_folio_charges", hotel)
    override = described_class.call(
      folio: folio,
      user: staff_user,
      transaction_type: "charge",
      category: nil,
      transaction_code_id: code.id,
      amount: "50.00",
      description: "Restaurant charge",
      options: { require_transaction_code: true, routing_override_reason: "Guest pays this one" }
    )

    expect(override.success?).to be(true)
    expect(override.transaction.booking_folio).to eq(folio)
    expect(override.transaction.metadata["route_source"]).to eq("manual_override")
  end

  it "posts generated tax children to the parent folio with real and legacy parent linkage" do
    hotel = folio.hotel
    booking = folio.booking
    company_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel)
    hotel.update!(sst_enabled: true)
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    code = hotel.transaction_codes.find_by!(system_key: "fnb_revenue")
    code.update!(is_taxable: true)
    code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: code, target_folio: company_folio)

    result = described_class.call(
      folio: company_folio,
      user: user,
      transaction_type: "charge",
      category: nil,
      transaction_code_id: code.id,
      amount: "50.00",
      description: "Restaurant charge",
      options: { require_transaction_code: true }
    )

    expect(result.success?).to be(true)
    tax = result.tax_transactions.sole
    expect(tax.booking_folio).to eq(company_folio)
    expect(tax.parent_transaction).to eq(result.transaction)
    expect(tax.metadata["parent_folio_transaction_id"]).to eq(result.transaction.id)
    expect(tax.metadata["parent_transaction_id"]).to eq(result.transaction.id)
    expect(tax.metadata["route_source"]).to eq("follows_parent")
    expect(tax.metadata["parent_transaction_code_code"]).to eq("FNB")
  end

  it "routes generated tax children by explicit child tax rules when present" do
    hotel = folio.hotel
    booking = folio.booking
    company_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, name: "Company Folio")
    tax_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, name: "Tax Folio")
    hotel.update!(sst_enabled: true, tourism_tax_enabled: true, tourism_tax_amount: 10)
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    code = hotel.transaction_codes.find_by!(system_key: "fnb_revenue")
    sst_code = hotel.transaction_codes.find_by!(system_key: "sst_tax")
    ttx_code = hotel.transaction_codes.find_by!(system_key: "tourism_tax")
    code.update!(is_taxable: true)
    code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
    code.transaction_code_taxes.create!(primary_tax_key: "tourism_tax")
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: code, target_folio: company_folio)
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: ttx_code, target_folio: tax_folio)

    result = described_class.call(
      folio: company_folio,
      user: user,
      transaction_type: "charge",
      category: nil,
      transaction_code_id: code.id,
      amount: "50.00",
      description: "Restaurant charge",
      options: { require_transaction_code: true }
    )

    expect(result.success?).to be(true)
    sst = result.tax_transactions.find { |transaction| transaction.transaction_code == sst_code }
    ttx = result.tax_transactions.find { |transaction| transaction.transaction_code == ttx_code }

    expect(sst.booking_folio).to eq(company_folio)
    expect(sst.metadata["route_source"]).to eq("follows_parent")
    expect(ttx.booking_folio).to eq(tax_folio)
    expect(ttx.metadata["route_source"]).to eq("routing_rule")
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
      description: "Refund credit balance",
      options: { metadata: { refund_source: "bank_transfer" } }
    )

    expect(result.success?).to be(true)
    expect(result.transaction.transaction_type).to eq("payment")
    expect(result.transaction.category).to eq("refund")
    expect(result.transaction.amount).to eq(-50.0)
    expect(result.transaction.metadata["refund_source"]).to eq("bank_transfer")
  end

  it "rejects manual refunds without a refund source" do
    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "payment",
      category: "refund",
      amount: "50.00",
      description: "Refund credit balance"
    )

    expect(result.success?).to be(false)
    expect(result.error).to eq("Refund source is required.")
  end

  it "rejects manual refunds with an invalid refund source" do
    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "payment",
      category: "refund",
      amount: "50.00",
      description: "Refund credit balance",
      options: { metadata: { refund_source: "crypto_wallet" } }
    )

    expect(result.success?).to be(false)
    expect(result.error).to eq("Refund source is not valid.")
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
