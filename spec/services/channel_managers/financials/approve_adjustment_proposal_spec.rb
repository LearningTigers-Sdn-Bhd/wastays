require "rails_helper"

RSpec.describe ChannelManagers::Financials::ApproveAdjustmentProposal do
  it "posts an idempotent staff-attributed adjustment from the durable proposal" do
    account = create(:account)
    hotel = create(:hotel, account: account)
    booking = create(:booking, hotel: hotel)
    create(:booking_folio, booking: booking, hotel: hotel)
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    snapshot = create(:ota_financial_snapshot, hotel: hotel, booking: booking,
      reconciliation_status: "rate_review_required",
      metadata: {
        "adjustment_proposal" => {
          "identity" => "proposal-1", "status" => "pending", "currency" => hotel.default_currency,
          "amount" => "12.50", "allocations" => [ { "booking_id" => booking.id, "amount" => "12.50" } ]
        }
      })
    user = create(:user, account: account, role: "admin")
    role = create(:role, account: account)
    permission = Permission.find_or_create_by!(slug: "post_folio_adjustments") { |record| record.name = "Post folio adjustments" }
    RolePermission.create!(role: role, permission: permission)
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    first = described_class.call(snapshot: snapshot, user: user)
    second = described_class.call(snapshot: snapshot, user: user)

    expect(first).to be_success
    expect(second).to be_success
    transactions = FolioTransaction.where("metadata->>'ota_adjustment_proposal_identity' = ?", "proposal-1")
    expect(transactions.count).to eq(1)
    expect(transactions.first).to have_attributes(amount: 12.5.to_d, transaction_type: "adjustment")
    expect(transactions.first.metadata).to include("approved_by_user_id" => user.id)
  end
end
