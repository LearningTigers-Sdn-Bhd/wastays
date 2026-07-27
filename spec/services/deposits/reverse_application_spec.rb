# frozen_string_literal: true

require "rails_helper"

RSpec.describe Deposits::ReverseApplication do
  def correction_actor(hotel)
    actor = create(:user, account: hotel.account)
    permission = Permission.find_or_create_by!(slug: "post_folio_corrections") { |record| record.name = "Post Folio Corrections" }
    role = create(:role, account: actor.account)
    role.permissions << permission
    create(:user_hotel_access, user: actor, hotel: hotel, role: role)
    actor
  end

  it "reverses the folio payment and restores deposit availability" do
    deposit = create(:deposit, :prepayment, amount: 100)
    folio = create(:booking_folio, booking: deposit.booking, hotel: deposit.hotel, currency: deposit.currency)
    application = Deposits::Apply.call(deposit: deposit, booking_folio: folio, amount: 100).movement

    result = described_class.call(movement: application, actor: correction_actor(deposit.hotel), reason: "Wrong folio")

    expect(result).to be_success
    expect(result.movement).to have_attributes(movement_type: "reverse", reversal_of: application, amount: 100.to_d)
    expect(result.transaction).to have_attributes(transaction_type: "payment", category: "refund", amount: -100.to_d)
    expect(deposit.reload).to have_attributes(status: "available", available_amount: 100.to_d)
    expect(deposit.booking.reload.payment_status).to eq("pending")
  end

  it "rejects a second reversal" do
    deposit = create(:deposit, :prepayment, amount: 100)
    folio = create(:booking_folio, booking: deposit.booking, hotel: deposit.hotel, currency: deposit.currency)
    application = Deposits::Apply.call(deposit: deposit, booking_folio: folio, amount: 50).movement
    actor = correction_actor(deposit.hotel)
    described_class.call(movement: application, actor: actor, reason: "Wrong folio")

    expect(described_class.call(movement: application.reload, actor: actor, reason: "Again").error).to include("already")
  end

  it "returns the original reversal for an idempotent retry" do
    deposit = create(:deposit, :prepayment, amount: 100)
    folio = create(:booking_folio, booking: deposit.booking, hotel: deposit.hotel, currency: deposit.currency)
    application = Deposits::Apply.call(deposit: deposit, booking_folio: folio, amount: 50).movement
    actor = correction_actor(deposit.hotel)

    first = described_class.call(movement: application, actor: actor, reason: "Wrong folio", operation_key: "reverse-once")
    second = described_class.call(movement: application, actor: actor, reason: "Wrong folio", operation_key: "reverse-once")

    expect(second).to be_success
    expect(second.movement).to eq(first.movement)
    expect(application.reload.reversal).to eq(first.movement)
  end
end
