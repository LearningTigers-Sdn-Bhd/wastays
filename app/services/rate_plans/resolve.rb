# frozen_string_literal: true

module RatePlans
  # Resolves the free-entry rate-plan autocomplete without making the browser
  # choose between "select" and "create" modes. A selected id is authoritative;
  # otherwise a normalized custom-plan name is matched within one hotel.
  class Resolve
    CREATABLE_ATTRIBUTES = %i[
      description base_occupancy extra_pax_charge single_supplement
      child_price_multiplier channex_children_fee channex_infant_fee
      rate_plan_age_bands_attributes
    ].freeze

    Result = Data.define(:rate_plan, :created, :error) do
      def success? = error.nil?
      def created? = created
    end

    def self.call(...) = new(...).call

    def initialize(hotel:, rate_plan_name:, rate_plan_id: nil, create_attributes: {})
      @hotel = hotel
      @rate_plan_id = rate_plan_id.presence
      @rate_plan_name = normalize(rate_plan_name)
      @create_attributes = create_attributes.respond_to?(:to_h) ? create_attributes.to_h : {}
    end

    def call
      return resolve_selected if rate_plan_id.present?
      return failure("Enter a rate plan name.") if rate_plan_name.blank?

      matches = eligible_scope.select { |plan| normalize(plan.name).casecmp?(rate_plan_name) }
      return success(matches.first, created: false) if matches.one?
      if matches.many?
        return failure("More than one rate plan has that name. Select a specific rate plan from the suggestions.")
      end

      plan = hotel.rate_plans.create!(new_plan_attributes)
      success(plan, created: true)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    private

    attr_reader :hotel, :rate_plan_id, :rate_plan_name, :create_attributes

    def resolve_selected
      plan = eligible_scope.find_by(id: rate_plan_id)
      return success(plan, created: false) if plan

      failure("Select an available custom rate plan for this property.")
    end

    def eligible_scope
      hotel.rate_plans.active.where(kind: "custom")
    end

    def new_plan_attributes
      supplied = create_attributes.with_indifferent_access.slice(*CREATABLE_ATTRIBUTES)
      supplied.merge(
        name: rate_plan_name,
        kind: "custom",
        currency: hotel.default_currency.presence || "MYR"
      )
    end

    def normalize(value)
      value.to_s.strip.gsub(/\s+/, " ")
    end

    def success(plan, created:)
      Result.new(rate_plan: plan, created: created, error: nil)
    end

    def failure(message)
      Result.new(rate_plan: nil, created: false, error: message)
    end
  end
end
