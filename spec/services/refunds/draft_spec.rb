require "rails_helper"

RSpec.describe Refunds::Draft do
  let(:booking) { create(:booking, status: "cancelled") }

  it "starts blank when there is no rejected request" do
    draft = described_class.new(booking:).call

    expect(draft.slice(*Refunds::Draft::CARRIED).values.compact).to be_empty
  end

  it "carries the reason and bank details of a rejected request, not the amount" do
    create(:refund_request, booking:, status: "rejected", reason: "Flight cancelled", bank_name: "Maybank",
                            account_holder_name: "Aisha Rahman", account_number: "1234", account_type: "savings",
                            refund_amount: 80)

    draft = described_class.new(booking:).call

    expect(draft).to have_attributes(reason: "Flight cancelled", bank_name: "Maybank", account_holder_name: "Aisha Rahman",
                                     account_number: "1234", account_type: "savings", refund_amount: nil)
    expect(draft).to be_new_record
  end
end
