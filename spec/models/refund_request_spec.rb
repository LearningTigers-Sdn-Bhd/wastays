require "rails_helper"

RSpec.describe RefundRequest, type: :model do
  let(:booking) { create(:booking, status: "confirmed") }

  subject(:refund_request) do
    build(:refund_request, booking: booking)
  end

  it "is valid with all required fields" do
    expect(refund_request).to be_valid
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:bank_name) }
    it { is_expected.to validate_presence_of(:account_holder_name) }
    it { is_expected.to validate_presence_of(:account_number) }
    it { is_expected.to validate_presence_of(:account_type) }
    it { is_expected.to validate_presence_of(:refund_amount) }

    it "allows blank reason" do
      refund_request.reason = ""
      expect(refund_request).to be_valid
    end

    it "rejects invalid status" do
      refund_request.status = "bogus"
      expect(refund_request).not_to be_valid
    end

    it "rejects invalid account_type" do
      refund_request.account_type = "bogus"
      expect(refund_request).not_to be_valid
    end

    it "prevents two refund requests for the same booking" do
      create(:refund_request, booking: booking)
      duplicate = build(:refund_request, booking: booking)
      expect(duplicate).not_to be_valid
    end
  end

  describe "status predicates" do
    %w[pending approved rejected completed].each do |s|
      it "responds true to #{s}?" do
        refund_request.status = s
        expect(refund_request.public_send(:"#{s}?")).to be true
      end
    end
  end
end
