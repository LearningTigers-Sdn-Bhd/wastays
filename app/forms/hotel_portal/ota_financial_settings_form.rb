# frozen_string_literal: true

module HotelPortal
  class OtaFinancialSettingsForm
    class MappingFields
      def initialize(values)
        @values = values.to_h.stringify_keys
      end

      def method_missing(name, *arguments)
        return @values[name.to_s] if arguments.empty?

        super
      end

      def respond_to_missing?(_name, _include_private = false) = true
    end

    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :mode, :string, default: "recommended"
    attribute :maximum_percentage, :decimal
    attribute :maximum_amount_per_room_night, :decimal
    attr_accessor :mapping_transaction_code_ids

    validates :mode, inclusion: { in: OtaRateVariancePolicy::MODES }
    validates :maximum_percentage, :maximum_amount_per_room_night,
      numericality: { greater_than_or_equal_to: 0 }, presence: true, if: :custom?

    attr_reader :hotel, :policy, :candidate_index, :current_user

    def initialize(hotel:, policy:, candidates:, current_user:, attributes: nil)
      @hotel = hotel
      @policy = policy
      @candidate_index = candidates.index_by(&:key)
      @current_user = current_user
      defaults = {
        mode: policy.mode,
        maximum_percentage: policy.maximum_percentage,
        maximum_amount_per_room_night: policy.maximum_amount_per_room_night,
        mapping_transaction_code_ids: candidates.to_h { |candidate| [ candidate.key, candidate.transaction_code_id ] }
      }
      super(defaults.merge((attributes || {}).to_h.symbolize_keys))
      self.mapping_transaction_code_ids ||= {}
    end

    def mapping_fields
      MappingFields.new(mapping_transaction_code_ids)
    end

    def save
      return false unless valid?

      validate_mapping_selections
      return false if errors.any?

      ApplicationRecord.transaction do
        save_policy!
        save_mappings!
      end
      true
    rescue ActiveRecord::RecordInvalid => error
      errors.add(:base, error.record.errors.full_messages.to_sentence)
      false
    end

    private

    def custom? = mode == "custom"

    def validate_mapping_selections
      mapping_transaction_code_ids.to_h.each do |key, transaction_code_id|
        candidate = candidate_index[key.to_s]
        next errors.add(:base, "A financial component changed. Reload and try again.") unless candidate
        next if transaction_code_id.blank?

        code = hotel.transaction_codes.active.find_by(id: transaction_code_id)
        expected_kind = { "tax" => "tax", "discount" => "adjustment" }.fetch(candidate.component_kind, "charge")
        errors.add(:base, "Choose a compatible transaction code for #{candidate.provider_name.humanize}.") unless code&.kind == expected_kind
      end
    end

    def save_policy!
      policy.assign_attributes(
        hotel: hotel,
        mode: mode,
        maximum_percentage: effective_percentage,
        maximum_amount_per_room_night: effective_amount_per_room_night,
        currency: policy.currency.presence || hotel.default_currency
      )
      policy.save!
    end

    def effective_percentage
      return maximum_percentage if custom?

      policy.maximum_percentage || OtaRateVariancePolicy::RECOMMENDED_MAX_PERCENTAGE
    end

    def effective_amount_per_room_night
      return maximum_amount_per_room_night if custom?

      policy.maximum_amount_per_room_night || OtaRateVariancePolicy::RECOMMENDED_MAX_AMOUNT_PER_ROOM_NIGHT
    end

    def save_mappings!
      mapping_transaction_code_ids.to_h.each do |key, transaction_code_id|
        candidate = candidate_index.fetch(key.to_s)
        mapping = candidate.mapping

        if transaction_code_id.blank?
          mapping&.update!(active: false)
          next
        end

        mapping ||= OtaFinancialComponentMapping.new(
          hotel: hotel,
          provider: candidate.provider,
          booking_source: candidate.booking_source,
          component_kind: candidate.component_kind,
          normalized_provider_type: candidate.provider_type,
          normalized_provider_name: candidate.provider_name
        )
        mapping.update!(transaction_code_id: transaction_code_id, created_by: current_user, active: true)
      end
    end
  end
end
