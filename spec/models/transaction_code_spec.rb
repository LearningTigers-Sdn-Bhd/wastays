# frozen_string_literal: true

require "rails_helper"

RSpec.describe TransactionCode, type: :model do
  subject(:transaction_code) { build(:transaction_code) }

  it { is_expected.to belong_to(:hotel) }
  it { is_expected.to have_many(:folio_transactions).dependent(:nullify) }
  it { is_expected.to have_many(:hotel_taxes).dependent(:nullify) }
  it { is_expected.to have_many(:transaction_code_taxes).dependent(:destroy) }
  it { is_expected.to have_many(:taxes).through(:transaction_code_taxes).source(:hotel_tax) }
  it { is_expected.to validate_presence_of(:system_key) }
  it { is_expected.to validate_presence_of(:code) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:kind) }
  it { is_expected.to validate_presence_of(:category) }

  it "keeps system_key separate from the hotel-facing code" do
    hotel = create(:hotel)
    code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    code.update!(code: "ROOM-CUSTOM")

    expect(code.system_key).to eq("room_revenue")
    expect(code.code).to eq("ROOM-CUSTOM")
  end
end
