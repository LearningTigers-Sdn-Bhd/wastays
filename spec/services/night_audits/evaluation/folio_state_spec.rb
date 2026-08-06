require "rails_helper"

RSpec.describe NightAudits::Evaluation::FolioState do
  it "calculates the outstanding folio balance" do
    folio = create(:booking_folio)
    create(:folio_transaction, :charge, booking_folio: folio, amount: 25)
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 10)

    expect(described_class.new.outstanding_balance(folio)).to eq(15.to_d)
  end
end
