# frozen_string_literal: true

module ChannelManagers
  module Financials
    class ResolveTransactionCode
      Result = Data.define(:transaction_code, :mapping_status)

      def self.call(hotel:, booking_source:, provider:, component:)
        new(hotel:, booking_source:, provider:, component:).call
      end

      def initialize(hotel:, booking_source:, provider:, component:)
        @hotel, @booking_source, @provider, @component = hotel, booking_source, provider, component
      end

      def call
        ::Financials::EnsureDefaultTransactionCodes.call(@hotel)
        return Result.new(transaction_code: code("room_revenue"), mapping_status: "canonical") if kind == "accommodation"

        mapping = mapping_scope.find_by(booking_source: @booking_source) || mapping_scope.find_by(booking_source_id: nil)
        return Result.new(transaction_code: mapping.transaction_code, mapping_status: "mapped") if mapping
        return Result.new(transaction_code: code("cleaning_revenue"), mapping_status: "canonical") if fee_kind? && cleaning?
        return Result.new(transaction_code: code("rebate"), mapping_status: "canonical") if kind == "discount"

        tax = matching_tax if kind == "tax"
        return Result.new(transaction_code: tax.transaction_code || tax.ensure_transaction_code, mapping_status: "mapped") if tax

        fallback = kind == "tax" ? "ota_unmapped_tax" : "ota_unmapped_fee"
        Result.new(transaction_code: code(fallback), mapping_status: "unmapped")
      end

      private

      def metadata = @component[:metadata].to_h
      def kind = @component[:kind].to_s
      def normalized(value) = BookingSource.normalize(value)
      def provider_name = metadata["name"].presence || metadata["title"].presence || kind.humanize
      def provider_type = metadata["type"].presence || metadata["category"].presence || ""
      def code(key) = @hotel.transaction_codes.find_by!(system_key: key)
      def fee_kind? = kind.in?(%w[fee service service_fee])
      def cleaning? = normalized(provider_name).include?("cleaning")

      def mapping_scope
        OtaFinancialComponentMapping.active.where(
          hotel: @hotel, provider: normalized(@provider), component_kind: mapping_kind,
          normalized_provider_name: normalized(provider_name), normalized_provider_type: normalized(provider_type)
        )
      end

      def mapping_kind
        kind == "service_fee" ? "service" : kind
      end

      def matching_tax
        name = normalized(provider_name)
        provider_rate = @component.dig(:metadata, "rate") || @component.dig(:metadata, "percentage") ||
          @component.dig(:metadata, "percent")
        @hotel.hotel_taxes.enabled.includes(:transaction_code).find do |tax|
          name_matches = normalized(tax.name) == name || normalized(tax.code) == name
          rate_matches = provider_rate.blank? || tax.amount.to_d == provider_rate.to_d
          name_matches && rate_matches
        end
      end
    end
  end
end
