# frozen_string_literal: true

require "set"

module ChannelManagers
  module Financials
    # Read-only inventory of OTA financial projection rollout readiness.
    #
    # Rows deliberately contain only operational identifiers and readiness
    # metadata. Guest details, payload metadata, payment data, and transaction
    # details are never loaded into or returned by the audit.
    class RolloutAudit
      CATEGORIES = %i[
        legacy_missing_snapshot
        balanced
        review_required
        safe_to_reproject
        blocked_by_posted_history
      ].freeze
      REVIEW_STATUSES = %w[unmapped_components total_mismatch rate_review_required].freeze

      Result = Data.define(:counts, :rows)

      def self.call(hotel:)
        new(hotel:).call
      end

      def initialize(hotel:)
        @hotel = hotel
      end

      def call
        targets = audit_targets
        posted_booking_ids = posted_booking_ids_for(targets)
        projected_component_ids = projected_component_ids_for(targets)

        rows = targets.map do |target|
          build_row(target, posted_booking_ids:, projected_component_ids:)
        end.sort_by { |row| [ CATEGORIES.index(row.fetch(:classification)), row.fetch(:channel_manager_reference).to_s, row.fetch(:snapshot_id).to_i ] }

        counts = CATEGORIES.index_with { |category| rows.count { |row| row[:classification] == category } }
        Result.new(counts: counts.freeze, rows: rows.map(&:freeze).freeze)
      end

      private

      Target = Data.define(:booking_id, :group_booking_id, :booking_ids, :channel_manager_reference, :snapshot)

      def audit_targets
        snapshots = OtaFinancialSnapshot.current
          .where(hotel_id: @hotel.id)
          .includes(:ota_financial_components)
          .order(:id)
          .to_a
        snapshots_by_target = snapshots.index_by { |snapshot| target_key(snapshot.booking_id, snapshot.group_booking_id) }

        channel_groups = @hotel.group_bookings.where.not(channel_manager_reference: [ nil, "" ])
          .select(:id, :channel_manager_reference).to_a
        group_ids = channel_groups.map(&:id) | snapshots.filter_map(&:group_booking_id)
        booking_ids_by_group = @hotel.bookings.where(group_booking_id: group_ids).pluck(:group_booking_id, :id)
          .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }

        targets = []
        @hotel.bookings.where(group_booking_id: nil).where.not(channel_manager_reference: [ nil, "" ])
          .select(:id, :channel_manager_reference).find_each do |booking|
          targets << Target.new(
            booking_id: booking.id,
            group_booking_id: nil,
            booking_ids: [ booking.id ],
            channel_manager_reference: booking.channel_manager_reference,
            snapshot: snapshots_by_target.delete(target_key(booking.id, nil))
          )
        end

        channel_groups.each do |group|
          targets << Target.new(
            booking_id: nil,
            group_booking_id: group.id,
            booking_ids: booking_ids_by_group.fetch(group.id, []),
            channel_manager_reference: group.channel_manager_reference,
            snapshot: snapshots_by_target.delete(target_key(nil, group.id))
          )
        end

        snapshots_by_target.each_value do |snapshot|
          targets << Target.new(
            booking_id: snapshot.booking_id,
            group_booking_id: snapshot.group_booking_id,
            booking_ids: snapshot.booking_id ? [ snapshot.booking_id ] : booking_ids_by_group.fetch(snapshot.group_booking_id, []),
            channel_manager_reference: snapshot.channel_manager_reference,
            snapshot: snapshot
          )
        end
        targets
      end

      def target_key(booking_id, group_booking_id)
        booking_id ? [ :booking, booking_id ] : [ :group_booking, group_booking_id ]
      end

      def posted_booking_ids_for(targets)
        booking_ids = targets.flat_map(&:booking_ids)
        return Set.new if booking_ids.empty?

        FolioTransaction.joins(:booking_folio)
          .where(booking_folios: { hotel_id: @hotel.id, booking_id: booking_ids.uniq })
          .distinct.pluck("booking_folios.booking_id").to_set
      end

      def projected_component_ids_for(targets)
        snapshot_ids = targets.filter_map { |target| target.snapshot&.id }
        return Set.new if snapshot_ids.empty?

        FolioForecastedCharge.joins(:booking_folio)
          .where(booking_folios: { hotel_id: @hotel.id })
          .where(status: "forecast")
          .where("folio_forecasted_charges.metadata->>'ota_financial_snapshot_id' IN (?)", snapshot_ids.map(&:to_s))
          .where("folio_forecasted_charges.metadata->>'ota_financial_component_id' IS NOT NULL")
          .pluck(Arel.sql("folio_forecasted_charges.metadata->>'ota_financial_component_id'"))
          .map!(&:to_i).to_set
      end

      def build_row(target, posted_booking_ids:, projected_component_ids:)
        snapshot = target.snapshot
        posted_history = target.booking_ids.any? { |booking_id| posted_booking_ids.include?(booking_id) }
        component_ids = snapshot ? snapshot.ota_financial_components.filter_map { |component| component.id if component.posting_amount.to_d.nonzero? } : []
        projected_count = component_ids.count { |component_id| projected_component_ids.include?(component_id) }

        {
          classification: classification_for(snapshot, posted_history:, component_ids:, projected_count:),
          booking_id: target.booking_id,
          group_booking_id: target.group_booking_id,
          snapshot_id: snapshot&.id,
          channel_manager_reference: target.channel_manager_reference,
          provider: snapshot&.provider,
          reconciliation_status: snapshot&.reconciliation_status,
          component_count: component_ids.size,
          projected_component_count: projected_count,
          posted_history: posted_history,
          adjustment_proposal: adjustment_proposal_for(target, posted_history)
        }
      end

      def adjustment_proposal_for(target, posted_history)
        snapshot = target.snapshot
        return unless posted_history && snapshot

        transactions = FolioTransaction.joins(:booking_folio)
          .where(booking_folios: { hotel_id: @hotel.id, booking_id: target.booking_ids })
          .where(voided_by_transaction_id: nil)
          .where("folio_transactions.metadata->>'nightly_charge_key' IS NOT NULL")
        posted_dates = transactions.distinct.pluck(
          Arel.sql("COALESCE(folio_transactions.metadata->>'stay_date', folio_transactions.posting_date::text)")
        ).map(&:to_date)
        desired = snapshot.ota_financial_components.where(booking_id: target.booking_ids, stay_date: posted_dates).sum(:posting_amount)
        actual = transactions.where("folio_transactions.metadata->>'ota_component_stable_key' IS NOT NULL").sum(:amount)
        {
          "amount" => (desired.to_d - actual.to_d).to_s("F"),
          "currency" => snapshot.currency,
          "action" => "staff_approval_required"
        }.freeze
      end

      def classification_for(snapshot, posted_history:, component_ids:, projected_count:)
        return :legacy_missing_snapshot unless snapshot
        return :blocked_by_posted_history if posted_history
        return :review_required if snapshot.reconciliation_status.in?(REVIEW_STATUSES)
        return :balanced if component_ids.any? && projected_count == component_ids.size

        :safe_to_reproject
      end
    end
  end
end
