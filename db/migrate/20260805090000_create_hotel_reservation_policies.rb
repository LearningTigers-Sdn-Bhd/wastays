# frozen_string_literal: true

class CreateHotelReservationPolicies < ActiveRecord::Migration[8.0]
  POLICY_TYPES = %w[late_checkout early_departure no_show cancellation].freeze
  PRICING_TYPES = %w[manual fixed percentage nights].freeze
  PERCENTAGE_BASES = %w[first_night total_stay remaining_nights].freeze
  REFUND_METHODS = %w[original_payment_method bank_transfer credit_note].freeze

  # How each policy is seeded, and the system key of the code it hangs off.
  # These values reproduce today's hardcoded behaviour exactly, so creating the
  # rows changes nothing until a hotel edits one.
  SEEDS = [
    { policy_type: "no_show", system_key: "no_show_revenue", active: true, pricing_type: "nights", rate_value: 1, allow_amount_override: false },
    { policy_type: "late_checkout", system_key: "late_checkout_revenue", active: true, pricing_type: "manual", rate_value: nil, allow_amount_override: true },
    { policy_type: "early_departure", system_key: "early_departure_revenue", active: true, pricing_type: "manual", rate_value: nil, allow_amount_override: true },
    { policy_type: "cancellation", system_key: "cancel_revenue", active: false, pricing_type: "manual", rate_value: nil, allow_amount_override: true }
  ].freeze

  class MigrationReservationPolicy < ActiveRecord::Base
    self.table_name = "hotel_reservation_policies"
  end

  class MigrationTransactionCode < ActiveRecord::Base
    self.table_name = "transaction_codes"
  end

  def up
    create_table :hotel_reservation_policies do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :transaction_code, null: false, foreign_key: true, index: { unique: true }
      t.string :policy_type, null: false
      t.boolean :active, null: false, default: true
      t.string :pricing_type, null: false, default: "manual"
      t.decimal :rate_value, precision: 12, scale: 4
      t.string :percentage_basis
      t.boolean :allow_amount_override, null: false, default: true
      t.text :description
      t.integer :refund_processing_days
      t.string :refund_method
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :hotel_cancellation_policy_tiers do |t|
      t.references :hotel_reservation_policy, null: false, foreign_key: true, index: { name: "index_cancellation_tiers_on_policy" }
      t.integer :days_before_arrival, null: false
      t.string :pricing_type, null: false, default: "percentage"
      t.decimal :rate_value, precision: 12, scale: 4, null: false
      t.string :percentage_basis
      t.integer :position, null: false, default: 0
      t.timestamps
      t.index %i[hotel_reservation_policy_id days_before_arrival], unique: true, name: "index_cancellation_tiers_on_policy_and_days"
      t.index %i[hotel_reservation_policy_id position], name: "index_cancellation_tiers_on_policy_and_position"
    end

    add_index :hotel_reservation_policies, %i[hotel_id policy_type], unique: true
    add_index :hotel_reservation_policies, %i[hotel_id position]

    add_policy_check_constraints
    add_tier_check_constraints

    backfill_policies
  end

  def down
    drop_table :hotel_cancellation_policy_tiers
    drop_table :hotel_reservation_policies
  end

  private

  def add_policy_check_constraints
    add_check_constraint :hotel_reservation_policies, in_list("policy_type", POLICY_TYPES), name: "hotel_reservation_policies_policy_type_allowed"
    add_check_constraint :hotel_reservation_policies, in_list("pricing_type", PRICING_TYPES), name: "hotel_reservation_policies_pricing_type_allowed"
    add_check_constraint :hotel_reservation_policies, "percentage_basis IS NULL OR #{in_list('percentage_basis', PERCENTAGE_BASES)}", name: "hotel_reservation_policies_percentage_basis_allowed"
    add_check_constraint :hotel_reservation_policies, "pricing_type <> 'percentage' OR percentage_basis IS NOT NULL", name: "hotel_reservation_policies_percentage_basis_required"
    add_check_constraint :hotel_reservation_policies, "pricing_type <> 'percentage' OR rate_value <= 100", name: "hotel_reservation_policies_percentage_maximum"
    add_check_constraint :hotel_reservation_policies, "rate_value IS NULL OR rate_value > 0", name: "hotel_reservation_policies_rate_value_positive"
    add_check_constraint :hotel_reservation_policies, "pricing_type <> 'nights' OR (rate_value IS NOT NULL AND rate_value = trunc(rate_value))", name: "hotel_reservation_policies_nights_whole"

    # No-show bills whole nights and nothing else. Its amount has to stay aligned
    # to the booking's per-night tax snapshot, which posts one tax line per night;
    # a percentage or flat fee would desync the fee from its own tax.
    add_check_constraint :hotel_reservation_policies, "policy_type <> 'no_show' OR pricing_type = 'nights'", name: "hotel_reservation_policies_no_show_nights_only"

    add_check_constraint :hotel_reservation_policies, "policy_type = 'cancellation' OR (refund_processing_days IS NULL AND refund_method IS NULL)", name: "hotel_reservation_policies_refund_cancellation_only"
    add_check_constraint :hotel_reservation_policies, "refund_method IS NULL OR #{in_list('refund_method', REFUND_METHODS)}", name: "hotel_reservation_policies_refund_method_allowed"
    add_check_constraint :hotel_reservation_policies, "refund_processing_days IS NULL OR refund_processing_days BETWEEN 0 AND 365", name: "hotel_reservation_policies_refund_processing_days_range"
  end

  def add_tier_check_constraints
    # A tier has to compute an amount on its own — there is no one at a keyboard
    # when a cancellation fee is assessed — so "manual" is not offered here.
    add_check_constraint :hotel_cancellation_policy_tiers, in_list("pricing_type", %w[fixed percentage nights]), name: "hotel_cancellation_policy_tiers_pricing_type_allowed"
    add_check_constraint :hotel_cancellation_policy_tiers, "days_before_arrival >= 0", name: "hotel_cancellation_policy_tiers_days_non_negative"

    # Unlike the parent policy, zero is meaningful: a 0% tier is how a hotel says
    # "free cancellation up to this point".
    add_check_constraint :hotel_cancellation_policy_tiers, "rate_value >= 0", name: "hotel_cancellation_policy_tiers_rate_value_non_negative"
    add_check_constraint :hotel_cancellation_policy_tiers, "pricing_type <> 'percentage' OR rate_value <= 100", name: "hotel_cancellation_policy_tiers_percentage_maximum"
    add_check_constraint :hotel_cancellation_policy_tiers, "percentage_basis IS NULL OR #{in_list('percentage_basis', PERCENTAGE_BASES)}", name: "hotel_cancellation_policy_tiers_percentage_basis_allowed"
    add_check_constraint :hotel_cancellation_policy_tiers, "pricing_type <> 'nights' OR rate_value = trunc(rate_value)", name: "hotel_cancellation_policy_tiers_nights_whole"
  end

  def in_list(column, values)
    "#{column} IN (#{values.map { |value| "'#{value}'" }.join(', ')})"
  end

  def backfill_policies
    now = Time.current

    SEEDS.each_with_index do |seed, index|
      MigrationTransactionCode.where(system_key: seed[:system_key]).order(:hotel_id, :id).find_each do |code|
        next if MigrationReservationPolicy.exists?(hotel_id: code.hotel_id, policy_type: seed[:policy_type])

        MigrationReservationPolicy.create!(
          hotel_id: code.hotel_id,
          transaction_code_id: code.id,
          policy_type: seed[:policy_type],
          active: seed[:active],
          pricing_type: seed[:pricing_type],
          rate_value: seed[:rate_value],
          allow_amount_override: seed[:allow_amount_override],
          position: index + 1,
          created_at: now,
          updated_at: now
        )
      end
    end
  end
end
