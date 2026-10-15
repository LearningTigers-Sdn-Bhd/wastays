# frozen_string_literal: true

# Lets a payment hold be set in days as well as hours, without a second column.
#
# `agent_payment_hold_hours` stays the one canonical value -- Bookings::PaymentHold
# and everything downstream read only that -- and the unit is a presentation
# choice the form makes on the way in and this concern re-derives on the way out.
# Storing the unit as well would mean two columns that can disagree about the
# same setting.
#
# A value that divides evenly into days reads back as days, which is what an
# admin who typed "3 days" expects to see. 36 hours has no whole-day form and
# reads back as hours. An unset hold reads back as days, because that is the
# unit the next person to fill it in almost certainly wants.
#
# Amount and unit arrive as two separate params and `assign_attributes` applies
# them in hash order, so neither writer converts anything on its own: they
# record what was typed and a `before_validation` resolves the pair. Converting
# in the writer would make the result depend on which field the form happened to
# render first.
module AgentPaymentHoldUnit
  extend ActiveSupport::Concern

  HOURS_PER_DAY = 24
  # Days first: a hold is set in days far more often than in hours, so it is
  # both the default unit and the one the menu offers first.
  UNITS = %w[days hours].freeze

  included do
    before_validation :resolve_agent_payment_hold
    after_validation :mirror_agent_payment_hold_errors
    # Cleared once written, so a later save on the same object -- a script that
    # assigns agent_payment_hold_hours directly, say -- is not silently
    # overwritten by what a form posted earlier. Not cleared in the
    # before_validation, because the after_validation below still needs to know
    # the amount was the field that was filled in.
    after_save :forget_assigned_agent_payment_hold
  end

  def agent_payment_hold_unit=(value)
    @agent_payment_hold_unit = value.to_s.strip.presence
  end

  # "days" when the stored hours are whole days, else "hours". A unit the form
  # posted wins, so a rejected save re-renders what was typed.
  def agent_payment_hold_unit
    return @agent_payment_hold_unit if @agent_payment_hold_unit.in?(UNITS)

    hours = agent_payment_hold_hours
    return "days" if hours.blank?
    return "hours" if hours < HOURS_PER_DAY || !(hours % HOURS_PER_DAY).zero?

    "days"
  end

  def agent_payment_hold_amount=(value)
    @agent_payment_hold_amount_assigned = true
    @agent_payment_hold_amount = value.to_s.strip
  end

  # The number to show beside the unit.
  def agent_payment_hold_amount
    return @agent_payment_hold_amount if @agent_payment_hold_amount_assigned

    hours = agent_payment_hold_hours
    return if hours.blank?

    agent_payment_hold_unit == "days" ? hours / HOURS_PER_DAY : hours
  end

  # "3 days" / "36 hours", for hints and placeholders.
  def agent_payment_hold_label
    hours = agent_payment_hold_hours
    return if hours.blank?

    unit = agent_payment_hold_unit
    amount = unit == "days" ? hours / HOURS_PER_DAY : hours
    "#{amount} #{amount == 1 ? unit.singularize : unit}"
  end

  private

  # Only when the form actually sent an amount. Otherwise every unrelated save
  # would rewrite the column.
  def resolve_agent_payment_hold
    return unless @agent_payment_hold_amount_assigned

    raw = @agent_payment_hold_amount.to_s.strip
    self.agent_payment_hold_hours =
      if raw.blank?
        nil
      elsif agent_payment_hold_unit == "days"
        raw.to_i * HOURS_PER_DAY
      else
        raw.to_i
      end
  end

  # The validation lives on the stored column, but the form field the admin can
  # see and fix is the amount. Without this the error renders nowhere.
  def mirror_agent_payment_hold_errors
    return unless @agent_payment_hold_amount_assigned

    errors.where(:agent_payment_hold_hours).each do |error|
      errors.add(:agent_payment_hold_amount, error.message)
    end
  end

  def forget_assigned_agent_payment_hold
    @agent_payment_hold_amount_assigned = false
    @agent_payment_hold_amount = nil
    @agent_payment_hold_unit = nil
  end
end
