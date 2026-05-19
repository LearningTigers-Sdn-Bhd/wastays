# frozen_string_literal: true

require "rails_helper"

RSpec.describe FolioTransaction, type: :model do
  describe "validations" do
    it { should belong_to(:booking_folio) }
    it { should belong_to(:user).optional }
    it { should belong_to(:reversal_of_transaction).optional }
    it { should belong_to(:voided_by_transaction).optional }
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

  describe "immutability" do
    it "prevents changing financial fields after creation" do
      transaction = create(:folio_transaction, amount: 100.0)

      expect(transaction.update(amount: 125.0)).to be(false)
      expect(transaction.errors[:base]).to include("Folio transactions are immutable. Post a reversing transaction instead.")
      expect(transaction.reload.amount).to eq(100.0)
    end

    it "allows linking the transaction that voided it" do
      transaction = create(:folio_transaction, amount: 100.0)
      reversal = create(:folio_transaction, booking_folio: transaction.booking_folio, amount: -100.0, transaction_type: :adjustment, category: "correction")

      expect(transaction.update(voided_by_transaction: reversal)).to be(true)
      expect(transaction.reload.voided_by_transaction).to eq(reversal)
    end

    it "prevents deletion" do
      transaction = create(:folio_transaction)

      expect(transaction.destroy).to be(false)
      expect(transaction.errors[:base]).to include("Folio transactions are immutable and cannot be deleted.")
      expect(described_class.exists?(transaction.id)).to be(true)
    end
  end
end
