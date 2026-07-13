require "rails_helper"

RSpec.describe GroupDeposits::RefundUnallocated do
  let(:group) { create(:group_booking) }
  let(:hotel) { group.hotel }
  let(:actor) { create(:user) }
  let(:deposit) { create(:group_deposit, group_booking: group, hotel: hotel, amount: 1_000) }

  it "partially refunds the unallocated amount and records who did it" do
    result = described_class.call(deposit: deposit, amount: 400, actor: actor, reason: "Group reduced headcount")

    expect(result).to be_success
    expect(result.deposit.reload).to have_attributes(
      refunded_amount: 400.to_d,
      status: "partially_refunded"
    )
    expect(result.deposit.refunded_at).to be_present
    expect(result.deposit.metadata).to include(
      "last_refund_reason" => "Group reduced headcount",
      "last_refund_actor_id" => actor.id
    )
  end

  it "marks the deposit fully refunded once the entire amount is returned" do
    result = described_class.call(deposit: deposit, amount: 1_000, actor: actor, reason: "Group cancelled")

    expect(result).to be_success
    expect(deposit.reload).to have_attributes(refunded_amount: 1_000.to_d, status: "refunded")
  end

  it "accumulates refunded_amount across multiple sequential refunds" do
    described_class.call(deposit: deposit, amount: 300, actor: actor, reason: "First reduction")
    result = described_class.call(deposit: deposit.reload, amount: 200, actor: actor, reason: "Second reduction")

    expect(result).to be_success
    expect(deposit.reload).to have_attributes(refunded_amount: 500.to_d, status: "partially_refunded")
  end

  it "rejects a refund that exceeds the unallocated amount" do
    result = described_class.call(deposit: deposit, amount: 1_001, actor: actor, reason: "Too much")

    expect(result).not_to be_success
    expect(result.error).to eq("Refund exceeds the unallocated amount.")
    expect(deposit.reload.refunded_amount).to eq(0.to_d)
  end

  it "accounts for already-allocated amounts when checking the available amount" do
    GroupDeposits::Allocate.call(
      deposit: deposit,
      booking_folio: create(:booking_folio, booking: create(:booking, hotel: hotel, group_booking: group, group_position: 1), hotel: hotel, currency: deposit.currency),
      amount: 300
    )

    result = described_class.call(deposit: deposit.reload, amount: 701, actor: actor, reason: "Too much after allocation")

    expect(result).not_to be_success
    expect(result.error).to eq("Refund exceeds the unallocated amount.")
  end

  it "rejects a zero or negative amount" do
    result = described_class.call(deposit: deposit, amount: 0, actor: actor, reason: "Zero refund")

    expect(result).not_to be_success
    expect(result.error).to eq("Refund amount must be positive.")
  end

  it "rejects a blank reason" do
    result = described_class.call(deposit: deposit, amount: 100, actor: actor, reason: "   ")

    expect(result).not_to be_success
    expect(result.error).to eq("Reason can't be blank.")
    expect(deposit.reload.refunded_amount).to eq(0.to_d)
  end
end
