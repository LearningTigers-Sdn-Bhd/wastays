# frozen_string_literal: true

require "rails_helper"

RSpec.describe Deposits::Deduct do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel) }
  let(:folio) { create(:booking_folio, booking: booking, hotel: hotel) }
  let(:user) { create(:user, account: hotel.account) }
  let(:deposit) { create(:deposit, booking: booking, hotel: hotel, amount: 100, currency: folio.currency) }
  let(:code) do
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    hotel.transaction_codes.find_by!(system_key: "cleaning_revenue")
  end

  before do
    role = create(:role, account: hotel.account)
    permission = Permission.find_by(slug: "post_folio_charges") || create(:permission, slug: "post_folio_charges", name: "Post folio charges")
    create(:role_permission, role: role, permission: permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current)
  end

  it "creates a charge and applies the full generated amount" do
    result = described_class.call(
      deposit: deposit, booking_folio: folio, amount: 35, transaction_code: code,
      actor: user, posting_date: hotel.current_business_date, operation_key: "deduct-cleaning-1"
    )

    expect(result).to be_success
    expect(result.charge_transactions.sum(&:amount)).to eq(35.to_d)
    expect(result.movements.sum(&:amount)).to eq(35.to_d)
    expect(deposit.reload.available_amount).to eq(65.to_d)
  end

  it "requires details for miscellaneous deductions" do
    misc = begin
      Financials::EnsureDefaultTransactionCodes.call(hotel)
      hotel.transaction_codes.find_by!(system_key: "misc_revenue")
    end

    result = described_class.call(
      deposit: deposit, booking_folio: folio, amount: 20, transaction_code: misc,
      actor: user, posting_date: hotel.current_business_date
    )

    expect(result).not_to be_success
    expect(result.error).to eq("Miscellaneous deduction details can't be blank.")
  end

  it "rolls back the charge when generated tax exceeds the available deposit" do
    hotel.update!(sst_enabled: true)
    code.update!(is_taxable: true)
    code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")

    expect {
      result = described_class.call(
        deposit: deposit, booking_folio: folio, amount: 95, transaction_code: code,
        actor: user, posting_date: hotel.current_business_date, operation_key: "deduct-tax-1"
      )
      expect(result).not_to be_success
      expect(result.error).to eq("Deduction total exceeds the available deposit amount.")
    }.not_to change(FolioTransaction, :count)
  end
end
