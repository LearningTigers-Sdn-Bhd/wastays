require "rails_helper"

RSpec.describe GroupDeposits::ReverseAllocation do
  let(:group) { create(:group_booking) }
  let(:hotel) { group.hotel }
  let(:booking) { create(:booking, hotel: hotel, group_booking: group, group_position: 1) }
  let!(:booking_room) { create(:booking_room, booking: booking) }
  let(:folio) { create(:booking_folio, booking: booking, hotel: hotel, is_primary: true) }
  let(:deposit) { create(:group_deposit, group_booking: group, hotel: hotel, amount: 1_000, currency: folio.currency) }
  let(:actor) { create(:user) }
  let(:allocation) { GroupDeposits::Allocate.call(deposit: deposit, booking_folio: folio, amount: 400).allocation }

  before { grant_correction_permission(actor, hotel) }

  def grant_correction_permission(user, hotel)
    permission = Permission.find_or_create_by!(slug: "post_folio_corrections") { |record| record.name = "Post Folio Corrections" }
    role = create(:role, account: user.account)
    role.permissions << permission
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
  end

  it "reverses an active allocation and restores the deposit's available amount" do
    allocation
    expect(deposit.reload.available_amount).to eq(600.to_d)

    result = described_class.call(allocation: allocation, actor: actor, reason: "Guest cancelled room")

    expect(result).to be_success
    expect(allocation.reload.status).to eq("reversed")
    expect(result.reversal).to have_attributes(status: "reversed", reversal_of_id: allocation.id, amount: 400.to_d)
    expect(deposit.reload.available_amount).to eq(1_000.to_d)
    expect(deposit.status).to eq("received")
  end

  it "fails when the reason is blank" do
    allocation

    result = described_class.call(allocation: allocation, actor: actor, reason: "  ")

    expect(result).not_to be_success
    expect(result.error).to eq("Reason can't be blank.")
    expect(allocation.reload.status).to eq("active")
  end

  it "fails when the allocation was already reversed" do
    allocation
    described_class.call(allocation: allocation, actor: actor, reason: "First reversal")

    result = described_class.call(allocation: allocation.reload, actor: actor, reason: "Second attempt")

    expect(result).not_to be_success
    expect(result.error).to eq("Allocation has already been reversed.")
  end

  it "leaves the deposit partially allocated when other allocations remain active" do
    allocation
    second_booking = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
    create(:booking_room, booking: second_booking)
    second_folio = create(:booking_folio, booking: second_booking, hotel: hotel, currency: folio.currency)
    other_allocation = GroupDeposits::Allocate.call(deposit: deposit.reload, booking_folio: second_folio, amount: 200).allocation

    described_class.call(allocation: allocation, actor: actor, reason: "Guest cancelled room")

    expect(deposit.reload.status).to eq("partially_allocated")
    expect(other_allocation.reload.status).to eq("active")
  end
end
