# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingPaymentInstalment do
  let(:booking) { create(:booking) }

  def build_instalment(**attrs)
    described_class.new({ booking: booking, position: 1, kind: "deposit", amount: 100, due_at: 3.days.from_now }.merge(attrs))
  end

  it "is valid with a stage, an amount and a deadline, and starts pending" do
    instalment = build_instalment

    expect(instalment).to be_valid
    expect(instalment).to be_status_pending
  end

  it "needs a positive amount" do
    expect(build_instalment(amount: 0)).not_to be_valid
  end

  it "allows one row per position on a booking" do
    build_instalment.save!

    expect(build_instalment(kind: "balance")).not_to be_valid
    expect(build_instalment(kind: "balance", position: 2)).to be_valid
  end

  it "rejects an unknown kind or status" do
    expect(build_instalment(kind: "bonus")).not_to be_valid
    expect(build_instalment(status: "lost")).not_to be_valid
  end

  it "lists a booking's instalments in stage order" do
    build_instalment(position: 2, kind: "balance").save!
    build_instalment.save!

    expect(booking.reload.payment_instalments.map(&:kind)).to eq(%w[deposit balance])
  end

  it "is removed with its booking" do
    build_instalment.save!

    expect { booking.destroy! }.to change(described_class, :count).by(-1)
  end
end
