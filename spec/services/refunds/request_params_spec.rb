require "rails_helper"

RSpec.describe Refunds::RequestParams do
  def call(fields) = described_class.new(ActionController::Parameters.new(refund_request: fields)).call

  it "stores the typed name when the guest picks Other bank" do
    result = call(bank_name: BankCatalog::OTHER, other_bank_name: " DBS Bank ", account_number: "1")

    expect(result[:bank_name]).to eq("DBS Bank")
    expect(result).not_to have_key(:other_bank_name)
  end

  it "keeps a listed bank and drops what the form does not send" do
    result = call(bank_name: "Maybank", status: "approved")

    expect(result.to_h).to eq("bank_name" => "Maybank")
  end
end
