# frozen_string_literal: true

module Cancellations
  # What the guest is shown about cancelling: a table of tiers, then the hotel's
  # own description beneath it as additional terms.
  #
  # It returns rows rather than a sentence on purpose. The numbers on a voucher come
  # from the same tier rows Cancellations::Quote charges from, so prose and engine
  # cannot drift apart and contradict each other in a dispute. The hotel's free-text
  # description carries only what tiers cannot express — "non-refundable during Hari
  # Raya", "deposit transferable" — and never restates the schedule.
  class PolicySummary
    Row = Data.define(:window, :charge, :days_before_arrival)

    Summary = Data.define(:rows, :description, :refund_note, :legacy_text) do
      # A summary with no rows and no words is nothing worth rendering.
      def present? = rows.any? || description.present? || refund_note.present? || legacy_text.present?
      def empty? = !present?
      def structured? = rows.any?

      # For the consumers that still have to hand a single string somewhere — the
      # AI concierge fact, the legacy `cancellation_policy` reader.
      def to_text
        parts(row_separator: "\n").join("\n\n").presence
      end

      # One line, for chat and any other surface that cannot hold a table.
      def to_line
        parts(row_separator: "; ").join(" ").squish.presence
      end

      private

      def parts(row_separator:)
        lines = rows.map { |row| "#{row.window}: #{row.charge}" }
        [ lines.presence&.join(row_separator), refund_note, description, structured? ? nil : legacy_text ].compact
      end
    end

    EMPTY = Summary.new(rows: [], description: nil, refund_note: nil, legacy_text: nil)

    REFUND_METHOD_LABELS = {
      "original_payment_method" => "the original payment method",
      "bank_transfer" => "bank transfer",
      "credit_note" => "a credit note"
    }.freeze

    class << self
      # The dual-read entry point: structured payload first, legacy prose only when
      # there is no structure to show.
      def call(snapshot_data: nil, legacy_text: nil)
        data = snapshot_data.presence || {}
        Summary.new(
          rows: rows_from(data["tiers"]),
          description: data["description"].presence,
          refund_note: refund_note_from(data),
          legacy_text: data["legacy_text"].presence || legacy_text.presence
        )
      end

      # A booking or a booking quote — both carry the same pair of columns.
      def for_record(record, legacy_text: nil)
        return EMPTY if record.blank?

        call(
          snapshot_data: record.cancellation_policy_snapshot_data,
          legacy_text: record.cancellation_policy_snapshot.presence || legacy_text
        )
      end

      # The hotel's policy as it stands right now, for surfaces that predate any
      # booking: the public hotel page, the AI concierge, a registration card.
      def for_hotel(hotel)
        return EMPTY if hotel.blank?

        call(snapshot_data: snapshot_for(hotel), legacy_text: hotel.property_policy&.cancellation_policy)
      end

      # The payload written into `cancellation_policy_snapshot_data`. It holds both
      # the tiers and the description, so the row records exactly what the guest saw.
      def snapshot_for(hotel)
        policy = live_policy(hotel)
        return {} if policy.blank? || !policy.active?

        {
          "description" => policy.description.presence,
          "refund_processing_days" => policy.refund_processing_days,
          "refund_method" => policy.refund_method,
          "tiers" => tiers_payload(policy)
        }.compact
      end

      private

      def live_policy(hotel)
        hotel.hotel_reservation_policies.includes(:cancellation_tiers).find_by(policy_type: "cancellation")
      end

      # Most generous band first — that is the order a guest reads a schedule in.
      # The rendered strings are stored, not just the numbers, so a document reprinted
      # years later still says what it said the day it was issued.
      def tiers_payload(policy)
        policy.cancellation_tiers.sort_by { |tier| -tier.days_before_arrival }.map do |tier|
          window, charge = split_label(tier)
          {
            "days_before_arrival" => tier.days_before_arrival,
            "window" => window,
            "charge" => charge,
            "pricing_type" => tier.pricing_type,
            "rate_value" => tier.rate_value.to_s,
            "percentage_basis" => tier.percentage_basis
          }
        end
      end

      # HotelCancellationPolicyTier#label is "<window>: <retention>", and no retention
      # label contains a colon — splitting keeps the wording single-sourced on the model.
      def split_label(tier)
        tier.label.split(": ", 2)
      end

      def rows_from(tiers)
        Array(tiers).filter_map do |tier|
          window = tier["window"].presence
          next if window.blank?

          Row.new(window: window, charge: tier["charge"].presence || "-", days_before_arrival: tier["days_before_arrival"].to_i)
        end
      end

      def refund_note_from(data)
        days = data["refund_processing_days"]
        method = REFUND_METHOD_LABELS[data["refund_method"]]
        return if days.blank? && method.blank?

        target = method.present? ? " to #{method}" : ""
        timing = days.present? ? " within #{days.to_i} #{'working day'.pluralize(days.to_i)}" : ""
        "Refunds are issued#{target}#{timing}."
      end
    end
  end
end
