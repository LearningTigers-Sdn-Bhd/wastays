require "rails_helper"

RSpec.describe GroupBookings::RemoveBooking, type: :service do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }
  let(:group) { create(:group_booking, hotel: hotel) }
  let(:booking) { create(:booking, hotel: hotel, group_booking: group, group_position: 1) }

  subject(:result) do
    described_class.call(group_booking: group, booking: booking, actor: user, reason: reason)
  end

  let(:reason) { "Guest requested separate billing" }

  it "detaches the booking from the group and records an audit log" do
    expect(result).to be_success
    expect(booking.reload.group_booking_id).to be_nil
    expect(booking.group_position).to be_nil

    log = BookingAuditLog.where(auditable: booking).order(:created_at).last
    expect(log.metadata["reason"]).to eq(reason)
    expect(log.source).to eq("group_booking")
  end

  it "fails when the reason is blank" do
    result = described_class.call(group_booking: group, booking: booking, actor: user, reason: "  ")

    expect(result).not_to be_success
    expect(result.error).to eq("Reason can't be blank.")
    expect(booking.reload.group_booking_id).to eq(group.id)
  end

  it "fails when the booking does not belong to the group" do
    outsider = create(:booking, hotel: hotel)

    result = described_class.call(group_booking: group, booking: outsider, actor: user, reason: reason)

    expect(result).not_to be_success
    expect(result.error).to eq("Booking does not belong to this group.")
  end

  context "when the booking has an active billing route applied via the group workflow" do
    let!(:group_rule) { create(:folio_routing_rule, booking: booking, hotel: hotel, active: true, source_type: "group") }

    it "deactivates the group-sourced route and logs the change" do
      expect(result).to be_success
      expect(group_rule.reload.active).to be(false)

      log = BookingAuditLog.where(auditable: booking).order(:created_at).last
      expect(log.category).to eq("financial")
      expect(log.new_value["active_group_billing_route_ids"]).to eq([])
    end
  end

  context "when the booking has an active billing route it set itself" do
    let!(:booking_rule) { create(:folio_routing_rule, booking: booking, hotel: hotel, active: true, source_type: "booking") }

    it "leaves the booking-sourced route untouched" do
      expect(result).to be_success
      expect(booking_rule.reload.active).to be(true)

      log = BookingAuditLog.where(auditable: booking).order(:created_at).last
      expect(log.category).to eq("other")
    end
  end

  context "when the booking has an inactive group-sourced billing route" do
    before { create(:folio_routing_rule, booking: booking, hotel: hotel, active: false, source_type: "group") }

    it "allows removal without touching the already-inactive route" do
      expect(result).to be_success
      expect(booking.reload.group_booking_id).to be_nil
    end
  end
end
