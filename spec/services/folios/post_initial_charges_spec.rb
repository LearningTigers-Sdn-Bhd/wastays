# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::PostInitialCharges do
  let(:booking) { create(:booking, check_in: Date.current, tax_lines: [{ "name" => "SST", "amount" => "12.00" }]) }
  let(:folio) { create(:booking_folio, booking: booking) }
  let(:user) { create(:user) }

  before do
    create(:booking_room, booking: booking, subtotal: 200.0)
  end

  it "posts accommodation and tax charges" do
    described_class.call(folio: folio, user: user)

    expect(folio.folio_transactions.charge.count).to eq(2)
    expect(folio.outstanding_balance).to eq(212.0)
  end

  it "raises when a transaction cannot be inserted" do
    failed_result = OpenStruct.new(success?: false, error: "posting blocked")
    insert_service = instance_double(Folios::InsertTransaction, call: failed_result)
    allow(Folios::InsertTransaction).to receive(:new).and_return(insert_service)

    expect {
      described_class.call(folio: folio, user: user)
    }.to raise_error(RuntimeError, /posting blocked/)
  end
end
