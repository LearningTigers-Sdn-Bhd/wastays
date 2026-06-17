# frozen_string_literal: true

require "rails_helper"

RSpec.describe FolioTransaction, type: :model do
  describe "validations" do
    it { should belong_to(:booking_folio) }
    it { should belong_to(:night_audit).optional }
    it { should belong_to(:user).optional }
    it { should belong_to(:reversal_of_transaction).optional }
    it { should belong_to(:voided_by_transaction).optional }
    it { should validate_presence_of(:amount) }
    it { should validate_presence_of(:transaction_type) }
    it { should validate_presence_of(:category) }
    it { should validate_presence_of(:description) }
    it { should validate_presence_of(:currency) }
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

    it "allows booking payments as positive payment transactions" do
      transaction = build(:folio_transaction, transaction_type: :payment, category: "booking_payment", amount: 100.0)

      expect(transaction).to be_valid
    end

    it "requires booking payments to be positive" do
      transaction = build(:folio_transaction, transaction_type: :payment, category: "booking_payment", amount: -100.0)

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

    it "requires a linked night audit to match the folio hotel and metadata" do
      folio = create(:booking_folio)
      other_audit = create(:night_audit)

      transaction = build(
        :folio_transaction,
        booking_folio: folio,
        night_audit: other_audit,
        metadata: { night_audit_id: other_audit.id }
      )

      expect(transaction).not_to be_valid
      expect(transaction.errors[:night_audit]).to include("must belong to the same hotel as the folio")
    end

    it "requires direct and metadata night audit links to agree" do
      folio = create(:booking_folio)
      audit = create(:night_audit, hotel: folio.hotel)

      transaction = build(:folio_transaction, booking_folio: folio, night_audit: audit, metadata: { night_audit_id: audit.id + 1 })

      expect(transaction).not_to be_valid
      expect(transaction.errors[:night_audit]).to include("must match metadata night_audit_id")
    end

    it "rejects an invalid direct night audit foreign key" do
      invalid_id = NightAudit.maximum(:id).to_i + 10_000
      transaction = create(:folio_transaction)

      expect { transaction.update_column(:night_audit_id, invalid_id) }.to raise_error(ActiveRecord::InvalidForeignKey)
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

    it "prevents changing catch_up_key after creation" do
      transaction = create(:folio_transaction, catch_up_key: "catch_up:1:2026-06-10:accommodation:1")

      expect(transaction.update(catch_up_key: "catch_up:1:2026-06-10:accommodation:2")).to be(false)
      expect(transaction.errors[:base]).to include("Folio transactions are immutable. Post a reversing transaction instead.")
    end
  end

  describe "database constraints" do
    it "rejects null descriptions" do
      transaction = create(:folio_transaction)

      expect { transaction.update_column(:description, nil) }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "rejects null currencies" do
      transaction = create(:folio_transaction)

      expect { transaction.update_column(:currency, nil) }.to raise_error(ActiveRecord::NotNullViolation)
    end
  end

  describe "GL code assignment" do
    let(:hotel) { create(:hotel) }
    let(:booking) { create(:booking, hotel: hotel) }
    let(:folio) { create(:booking_folio, hotel: hotel, booking: booking) }

    before do
      hotel.hotel_general_ledger_maps.find_by(transaction_category: "accommodation").update!(gl_code: "4010")
    end

    it "automatically assigns gl_code from hotel mapping on creation" do
      transaction = create(:folio_transaction, booking_folio: folio, category: "accommodation")
      expect(transaction.gl_code).to eq("4010")
    end

    it "automatically assigns transaction_code from category on creation" do
      transaction = create(:folio_transaction, booking_folio: folio, category: "accommodation")

      expect(transaction.transaction_code.system_key).to eq("room_revenue")
    end

    it "uses tax line type to assign SST transaction code" do
      transaction = create(
        :folio_transaction,
        booking_folio: folio,
        category: "tax",
        metadata: { tax_line: { type: "sst" } }
      )

      expect(transaction.transaction_code.system_key).to eq("sst_tax")
      expect(transaction.transaction_code.code).to eq("TAX_SST")
    end

    it "uses hotel tax id to assign custom tax transaction code" do
      tax = create(:hotel_tax, hotel: hotel, name: "Dewan Bandaraya Kota Kinabalu", amount: 5)

      transaction = create(
        :folio_transaction,
        booking_folio: folio,
        category: "tax",
        metadata: { tax_line: { tax_id: tax.id, type: "custom" } }
      )

      expect(transaction.transaction_code).to eq(tax.transaction_code)
      expect(transaction.gl_code).to eq(tax.transaction_code.gl_account_code)
    end

    it "does not overwrite gl_code if manually provided" do
      transaction = create(:folio_transaction, booking_folio: folio, category: "accommodation", gl_code: "MANUAL-GL")
      expect(transaction.gl_code).to eq("MANUAL-GL")
    end

    it "uses transaction code GL account when a legacy mapping is missing" do
      hotel.hotel_general_ledger_maps.where(transaction_category: "other").delete_all
      transaction = create(:folio_transaction, booking_folio: folio, category: "other")

      expect(transaction.gl_code).to eq("4090")
      expect(transaction.transaction_code.system_key).to eq("misc_revenue")
    end
  end
end
