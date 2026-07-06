# frozen_string_literal: true

require "rails_helper"

RSpec.describe GroupBillingChanges::Batch do
  let(:group) { create(:group_booking) }
  let(:hotel) { group.hotel }
  let(:actor) { create(:user) }
  let(:arrangement) { create(:group_billing_arrangement, :company, group_booking: group, hotel: hotel) }
  let!(:code) { create(:transaction_code, hotel: hotel, category: "accommodation", code: "ROOMX") }

  def child(position)
    booking = create(:booking, hotel: hotel, group_booking: group, group_position: position)
    create(:booking_room, booking: booking)
    guest = create(:booking_guest, booking: booking, is_primary: true)
    party = guest.booking_billing_party
    create(:booking_folio, booking: booking, hotel: hotel, is_primary: true, booking_billing_party: party)
    booking
  end

  def attributes(bookings, key: SecureRandom.uuid)
    { group_booking: group, actor: actor, booking_ids: bookings.map(&:id), arrangement_id: arrangement.id,
      categories: [ "accommodation" ], inclusion_changes: {}, idempotency_key: key }
  end

  it "previews and applies group routes only to selected child bookings" do
    selected = child(1)
    untouched = child(2)
    charge = create(:folio_transaction, booking_folio: selected.booking_folio, transaction_code: code,
      transaction_type: "charge", category: "accommodation", amount: 125)
    attrs = attributes([ selected ])
    preview = described_class.preview(**attrs)

    expect(preview.count).to eq(1)
    expect(preview.amount).to eq(charge.amount)

    result = described_class.call(**attrs, freshness_token: preview.freshness_token,
      confirmation: "future_only", reason: "Company covers rooms")

    expect(result).to be_success
    expect(selected.folio_routing_rules.active.find_by(transaction_code: code)).to have_attributes(source_type: "group")
    expect(untouched.folio_routing_rules.active.where(transaction_code: code)).to be_empty
    expect(selected.booking_folios.where(payer_type: "company").count).to eq(1)
    expect(group.group_billing_change_batches.where(status: "completed").count).to eq(1)
  end

  it "preserves booking-local routing exceptions unless replacement is explicit" do
    booking = child(1)
    local = create(:folio_routing_rule, booking: booking, hotel: hotel, transaction_code: code,
      target_folio: booking.booking_folio, source_type: "booking")
    attrs = attributes([ booking ])
    preview = described_class.preview(**attrs)

    expect(described_class.call(**attrs, freshness_token: preview.freshness_token,
      confirmation: "future_only", reason: "Keep local route")).to be_success
    expect(local.reload).to be_active
  end

  it "rejects a stale preview" do
    booking = child(1)
    attrs = attributes([ booking ])
    preview = described_class.preview(**attrs)
    booking.booking_folio.update!(name: "Changed after preview")

    result = described_class.call(**attrs, freshness_token: preview.freshness_token,
      confirmation: "future_only", reason: "Stale")

    expect(result).not_to be_success
    expect(result.error).to include("stale")
  end

  it "makes a completed idempotency key safe to retry" do
    booking = child(1)
    attrs = attributes([ booking ], key: "same-request")
    preview = described_class.preview(**attrs)
    first = described_class.call(**attrs, freshness_token: preview.freshness_token,
      confirmation: "future_only", reason: "Approved")
    second = described_class.call(**attrs, freshness_token: preview.freshness_token,
      confirmation: "future_only", reason: "Approved")

    expect(first).to be_success
    expect(second).to be_success
    expect(group.group_billing_change_batches.count).to eq(1)
    expect(booking.folio_routing_rules.active.where(transaction_code: code).count).to eq(1)
  end

  it "rolls every selected child back when a later child fails" do
    first = child(1)
    second = child(2)
    attrs = attributes([ first, second ], key: "atomic-request")
    preview = described_class.preview(**attrs)
    allow(BookingAuditLog).to receive(:create!).and_wrap_original do |method, attributes|
      raise ActiveRecord::RecordInvalid.new(second) if attributes[:auditable] == second
      method.call(attributes)
    end

    result = described_class.call(**attrs, freshness_token: preview.freshness_token,
      confirmation: "future_only", reason: "Must be atomic")

    expect(result).not_to be_success
    expect(first.reload.folio_routing_rules).to be_empty
    expect(second.reload.folio_routing_rules).to be_empty
    expect(group.group_billing_change_batches.reload).to be_empty
  end
end
