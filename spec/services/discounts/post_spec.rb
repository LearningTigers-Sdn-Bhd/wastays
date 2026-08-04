require "rails_helper"

RSpec.describe Discounts::Post do
  it "posts one negative configured discount with calculation metadata" do
    folio = create(:booking_folio)
    user = create(:user, account: folio.hotel.account)
    permission = Permission.find_or_create_by!(slug: "post_folio_adjustments") { |record| record.name = "Post Folio Adjustments" }
    role = create(:role, account: folio.hotel.account, permissions: [ permission ])
    create(:user_hotel_access, user:, hotel: folio.hotel, role:)
    create(:folio_transaction, booking_folio: folio, amount: 100, category: "accommodation")
    discount = create(:hotel_discount, hotel: folio.hotel, pricing_type: "percentage", rate_value: 10,
      application_scope: "room_charges", allow_amount_override: false)
    preview = Discounts::Quote.call(discount:, folio:, posting_date: Date.current, preview: true)

    result = described_class.call(discount:, folio:, user:, posting_date: Date.current, requested_amount: nil,
      expected_fingerprint: preview.fingerprint, description: "Service recovery", reference: "MGR-1")

    expect(result).to be_success
    expect(result.transaction).to have_attributes(amount: -10.to_d, transaction_type: "adjustment", category: "discount",
      transaction_code: discount.transaction_code)
    expect(result.transaction.description).to include(discount.name, "10.00%", "MYR 100.00", "Service recovery")
    expect(result.transaction.metadata).to include("hotel_discount_id" => discount.id, "reference" => "MGR-1")
  end
end
