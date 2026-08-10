# frozen_string_literal: true

require "ostruct"

module ChannelManagers
  # Stores the channel manager's settlement expectation only. Allocation to a
  # booking folio, receipt creation, and actual payment posting deliberately
  # belong to later workflows.
  class PersistSettlement
    SAFE_METADATA_KEYS = %w[
      ota_name
      provider_status
      payment_collect
      payment_type
      source_resolution
      collection_by
      settlement_method
    ].freeze

    Result = Struct.new(:status, :settlement, :message, keyword_init: true) do
      def success?
        !needs_attention? && !failed?
      end

      def created?
        status == :created
      end

      def updated?
        status == :updated
      end

      def ignored?
        status == :ignored
      end

      def needs_attention?
        status == :needs_attention
      end

      def failed?
        status == :failed
      end

      def record
        settlement
      end

      alias channel_settlement settlement
    end

    def self.call(...)
      new(...).call
    end

    def initialize(hotel: nil, settlement_data: nil, settlement: nil, booking_data: nil)
      @data = settlement_data || settlement || booking_data&.fetch(:settlement, nil) || {}
      @data = @data.to_h.with_indifferent_access
      @hotel = hotel || @data[:hotel] || booking_data&.fetch(:hotel, nil)
    end

    def call
      return needs_attention("Settlement hotel is required") unless @hotel.present?

      source = BookingSource.find_by(key: value(:booking_source_key).to_s)
      unless ota_source?(source)
        return needs_attention("Settlement booking source is unknown, inactive, or not an OTA")
      end

      provider = value(:provider).to_s.strip.downcase
      reference = value(:channel_manager_reference).to_s.strip
      return needs_attention("Settlement provider and channel manager reference are required") if provider.blank? || reference.blank?

      normalized = normalized_attributes(source: source, provider: provider, reference: reference)
      record, result_status = persist(normalized, provider: provider, reference: reference)
      Result.new(status: result_status, settlement: record, message: result_message(result_status))
    rescue ActiveRecord::RecordInvalid => e
      Result.new(status: :failed, settlement: nil, message: e.record.errors.full_messages.to_sentence)
    rescue StandardError => e
      Rails.logger.error("Persist settlement failed: #{e.class}: #{e.message}")
      Result.new(status: :failed, settlement: nil, message: e.message)
    end

    private

    def value(key)
      @data[key]
    end

    def ota_source?(source)
      source.present? && source.active? && source.kind == "ota"
    end

    def normalized_attributes(source:, provider:, reference:)
      gross_amount = decimal_amount(value(:gross_amount))
      commission_amount = [ decimal_amount(value(:commission_amount)), gross_amount ].min
      currency = valid_currency(value(:currency))
      status = value(:status).to_s
      status = "needs_attention" unless ChannelSettlement::STATUSES.include?(status)

      {
        hotel: @hotel,
        booking_source: source,
        provider: provider,
        channel_manager_reference: reference,
        latest_revision_id: value(:revision_id).presence&.to_s,
        collection_by: normalize_enum(value(:collection_by), ChannelSettlement::COLLECTION_RESPONSIBILITIES, "unknown"),
        settlement_method: normalize_enum(value(:settlement_method), ChannelSettlement::SETTLEMENT_METHODS, "unknown"),
        status: status,
        currency: currency,
        gross_amount: gross_amount,
        commission_amount: commission_amount,
        expected_net_amount: gross_amount - commission_amount,
        virtual_card_is_virtual: virtual_card_value(:is_virtual),
        virtual_card_currency: valid_currency(virtual_card_value(:currency), allow_nil: true),
        virtual_card_available_balance: decimal_or_nil(virtual_card_value(:available_balance)),
        virtual_card_effective_date: date_or_nil(virtual_card_value(:effective_date)),
        virtual_card_expiration_date: date_or_nil(virtual_card_value(:expiration_date)),
        metadata: safe_metadata
      }
    end

    def persist(attributes, provider:, reference:)
      ActiveRecord::Base.transaction do
        record = @hotel.channel_settlements.lock.find_by(
          provider: provider,
          channel_manager_reference: reference
        )

        if record.present? && !newer_revision?(record.latest_revision_id, attributes[:latest_revision_id])
          next [ record, :ignored ]
        end

        result_status = record&.persisted? ? :updated : :created
        record ||= @hotel.channel_settlements.new
        record.assign_attributes(attributes)
        record.save!
        [ record, result_status ]
      end
    end

    def newer_revision?(current_revision, incoming_revision)
      return true if current_revision.blank?
      return false if incoming_revision.blank?
      return false if current_revision.to_s == incoming_revision.to_s

      comparison = compare_revisions(current_revision, incoming_revision)
      comparison.present? && comparison.positive?
    end

    # Channex currently emits numeric revisions, but some endpoints expose a
    # timestamp or a rev_123-style identifier. Opaque identifiers are never
    # guessed at: changing a known revision without an ordering proof is unsafe.
    def compare_revisions(current_revision, incoming_revision)
      current_key = revision_key(current_revision)
      incoming_key = revision_key(incoming_revision)
      return nil unless current_key && incoming_key && current_key.first == incoming_key.first

      incoming_key.last <=> current_key.last
    end

    def revision_key(value)
      string = value.to_s.strip
      return [ :number, string.to_i ] if string.match?(/\A\d+\z/)
      if (match = string.match(/\A(?:rev(?:ision)?[_-]?)?(\d+)\z/i))
        return [ :number, match[1].to_i ]
      end

      [ :time, DateTime.parse(string).to_time.to_f ]
    rescue ArgumentError, TypeError
      nil
    end

    def normalize_enum(value, allowed, fallback)
      normalized = value.to_s
      allowed.include?(normalized) ? normalized : fallback
    end

    def virtual_card_value(key)
      virtual_card = value(:virtual_card)
      return nil unless virtual_card.respond_to?(:[])

      virtual_card[key.to_s] || virtual_card[key]
    end

    def safe_metadata
      metadata = value(:metadata)
      return {} unless metadata.respond_to?(:[])

      SAFE_METADATA_KEYS.each_with_object({}) do |key, result|
        item = metadata[key] || metadata[key.to_sym]
        result[key] = item.to_s if item.present?
      end
    end

    def decimal_amount(value)
      value = value[:amount] || value["amount"] if value.is_a?(Hash)
      BigDecimal(value.to_s)
    rescue ArgumentError, TypeError
      BigDecimal("0")
    end

    def decimal_or_nil(value)
      return nil if value.blank?

      decimal_amount(value)
    end

    def valid_currency(value, allow_nil: false)
      return nil if allow_nil && value.blank?

      normalized = CurrencyCatalog.normalize(value, fallback: @hotel.default_currency || "MYR")
      CurrencyCatalog.valid?(normalized) ? normalized : (@hotel.default_currency || "MYR")
    end

    def date_or_nil(value)
      return nil if value.blank?
      return value if value.is_a?(Date)

      Date.parse(value.to_s)
    rescue Date::Error, ArgumentError, TypeError
      nil
    end

    def needs_attention(message)
      Result.new(status: :needs_attention, settlement: nil, message: message)
    end

    def result_message(status)
      {
        created: "Settlement persisted",
        updated: "Settlement revision updated",
        ignored: "Duplicate or older settlement revision ignored"
      }.fetch(status)
    end
  end
end
