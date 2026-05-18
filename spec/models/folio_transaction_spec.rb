# frozen_string_literal: true

require "rails_helper"

RSpec.describe FolioTransaction, type: :model do
  describe "validations" do
    it { should belong_to(:booking_folio) }
    it { should belong_to(:user).optional }
    it { should validate_presence_of(:amount) }
    it { should validate_presence_of(:transaction_type) }
    it { should validate_presence_of(:category) }
    it { should validate_presence_of(:description) }
    it { should validate_presence_of(:posting_date) }

    it "requires charges to be positive" do
      transaction = build(:folio_transaction, transaction_type: :charge, category: "accommodation", amount: -100.0)

      expect(transaction).not_to be_valid
      expect(transaction.errors[:amount]).to include("must be positive for charge transactions")
    end

    it "requires non-refund payments to be positive" do
      transaction = build(:folio_transaction, transaction_type: :payment, category: "gateway_payment", amount: -100.0)

      expect(transaction).not_to be_valid
      expect(transaction.errors[:amount]).to include("must be positive for payment transactions")
    end

    it "allows advance deposits as positive payment transactions" do
      transaction = build(:folio_transaction, transaction_type: :payment, category: "advance_deposit", amount: 100.0)

      expect(transaction).to be_valid
    end

    it "requires advance deposits to be positive" do
      transaction = build(:folio_transaction, transaction_type: :payment, category: "advance_deposit", amount: -100.0)

      expect(transaction).not_to be_valid
      expect(transaction.errors[:amount]).to include("must be positive for payment transactions")
    end

    it "requires refunds to be negative payment transactions" do
      transaction = build(:folio_transaction, transaction_type: :payment, category: "refund", amount: 100.0)

      expect(transaction).not_to be_valid
      expect(transaction.errors[:amount]).to include("must be negative for refund transactions")
    end

    it "allows positive and negative adjustments" do
      positive_adjustment = build(:folio_transaction, transaction_type: :adjustment, category: "correction", amount: 25.0)
      negative_adjustment = build(:folio_transaction, transaction_type: :adjustment, category: "discount", amount: -25.0)

      expect(positive_adjustment).to be_valid
      expect(negative_adjustment).to be_valid
    end

    it "rejects categories outside the transaction type" do
      transaction = build(:folio_transaction, transaction_type: :charge, category: "gateway_payment", amount: 100.0)

      expect(transaction).not_to be_valid
      expect(transaction.errors[:category]).to include("is not allowed for charge transactions")
    end
  end
end
