# frozen_string_literal: true

module HotelPortal
  class ChannelSettlementReceiptForm
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :booking_source_id, :integer
    attribute :hotel_payment_method_id, :integer
    attribute :settlement_method, :string, default: "bank_transfer"
    attribute :amount, :decimal
    attribute :currency, :string
    attribute :received_at, :datetime
    attribute :external_reference, :string
    attribute :notes, :string
    attr_accessor :allocations

    validates :booking_source_id, :hotel_payment_method_id, :settlement_method,
      :amount, :currency, :received_at, presence: true
    validates :amount, numericality: { greater_than: 0 }, allow_nil: true
    validates :settlement_method, inclusion: { in: ChannelSettlementReceipt::SETTLEMENT_METHODS }
    validates :currency, inclusion: { in: ->(_) { CurrencyCatalog.codes } }

    def initialize(attributes = {})
      super
      self.allocations ||= {}
    end
  end
end
