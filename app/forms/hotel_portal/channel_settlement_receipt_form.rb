# frozen_string_literal: true

module HotelPortal
  class ChannelSettlementReceiptForm
    RECEIPT_SETTLEMENT_METHODS = %w[bank_transfer virtual_card].freeze

    class AllocationFields
      include ActiveModel::Model

      def initialize(values = {})
        @values = values.to_h.stringify_keys
      end

      def read_attribute_for_validation(attribute)
        @values[attribute.to_s]
      end

      def method_missing(name, *arguments)
        return @values[name.to_s] if arguments.empty? && name.to_s.match?(/\A\d+\z/)

        super
      end

      def respond_to_missing?(name, include_private = false)
        name.to_s.match?(/\A\d+\z/) || super
      end
    end

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
    attribute :allocation_search, :string
    attr_accessor :allocations

    validates :booking_source_id, :hotel_payment_method_id, :settlement_method,
      :amount, :currency, :received_at, presence: true
    validates :amount, numericality: { greater_than: 0 }, allow_nil: true
    validates :settlement_method, inclusion: { in: RECEIPT_SETTLEMENT_METHODS }
    validates :currency, inclusion: { in: ->(_) { CurrencyCatalog.codes } }

    def initialize(attributes = {})
      super
      self.allocations ||= {}
    end

    def allocation_fields
      AllocationFields.new(allocations)
    end
  end
end
