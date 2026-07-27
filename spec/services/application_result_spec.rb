# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationResult do
  let(:result_class) { described_class.define(:folio, :balance) }

  it "builds a success that answers success? and nil-fills what the caller omits" do
    result = result_class.success(folio: "F")

    expect(result).to be_success
    expect(result.error).to be_nil
    expect(result.folio).to eq("F")
    expect(result.balance).to be_nil
  end

  it "builds a failure carrying the error and nil-fills the rest" do
    result = result_class.failure("Folio is already closed.", folio: "F")

    expect(result).not_to be_success
    expect(result.error).to eq("Folio is already closed.")
    expect(result.folio).to eq("F")
    expect(result.balance).to be_nil
  end

  it "raises on a member the result does not have, where OpenStruct answered nil" do
    expect { result_class.success(folio: "F").sucess? }.to raise_error(NoMethodError)
  end

  it "freezes the result" do
    expect(result_class.success(folio: "F")).to be_frozen
  end
end
