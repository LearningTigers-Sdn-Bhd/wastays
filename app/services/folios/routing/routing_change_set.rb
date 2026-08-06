# frozen_string_literal: true

module Folios
  module Routing
    # Validates a submitted routes hash against the booking's routing matrix and
    # answers with the parent, child and tax changes it implies.
    #
    # The stages run in order and stop at the first one that fails, because a
    # later stage rejects the same bad input with a different message and would
    # otherwise overwrite the more specific one. Within a stage every entry is
    # still checked, and the last failure is the one reported.
    class RoutingChangeSet
      attr_reader :changes, :child_changes, :tax_changes, :error

      def self.build(booking:, routes:)
        new(booking: booking, routes: routes).build
      end

      def initialize(booking:, routes:)
        @booking = booking
        @routes = routes.to_h
        @changes = []
        @child_changes = []
        @tax_changes = []
      end

      def build
        @changes = validated_changes
        return self if @error

        @child_changes = validated_child_changes
        return self if @error

        @tax_changes = validated_tax_changes
        self
      end

      def valid?
        @error.nil?
      end

      def all_changes
        @changes + @child_changes
      end

      def any?
        @changes.any? || @child_changes.any? || @tax_changes.any?
      end

      private

      def matrix
        @matrix ||= RoutingMatrix.new(booking: @booking)
      end

      def rows
        @rows ||= matrix.rows.index_by { |row| row.code.id.to_s }
      end

      def folios
        @folios ||= matrix.folios.index_by { |folio| folio.id.to_s }
      end

      def validated_changes
        @routes.filter_map do |code_id, attributes|
          row = rows[code_id.to_s]
          attrs = attributes.respond_to?(:to_h) ? attributes.to_h : {}
          folio = folios[attrs["target_folio_id"].to_s]
          party_id = attrs["billing_party_id"].presence
          unless row && folio
            @error = "A selected transaction code or folio is unavailable."
            next
          end
          unless folio.open?
            @error = "Billing routes can only target an open folio."
            next
          end
          unless folio.booking_billing_party_id.to_s == party_id.to_s
            @error = "Target folio must belong to the selected billing party."
            next
          end
          next if row.target_folio&.id == folio.id

          { row:, folio: }
        end
      end

      def validated_tax_changes
        @routes.flat_map do |code_id, attributes|
          row = rows[code_id.to_s]
          taxes = attributes.respond_to?(:to_h) ? attributes.to_h.fetch("taxes", {}) : {}
          unless row
            @error = "A selected transaction code is unavailable."
            next []
          end
          allowed = row.children.index_by(&:key)
          taxes.filter_map do |key, value|
            unless allowed.key?(key)
              @error = "A selected tax inclusion is unavailable."
              next
            end
            included = ActiveModel::Type::Boolean.new.cast(value)
            child = allowed[key]
            next if child.included == included

            { row:, key:, included: }
          end
        end
      end

      def validated_child_changes
        @routes.flat_map do |code_id, attributes|
          row = rows[code_id.to_s]
          children = attributes.respond_to?(:to_h) ? attributes.to_h.fetch("children", {}) : {}
          unless row
            @error = "A selected transaction code is unavailable."
            next []
          end
          allowed = row.children.index_by(&:key)
          children.filter_map do |key, raw|
            child = allowed[key]
            attrs = raw.respond_to?(:to_h) ? raw.to_h : {}
            unless child
              @error = "A selected attached tax or charge is unavailable."
              next
            end
            choice = attrs["billing_party_choice"].presence
            mode = choice.present? ? (choice.in?(%w[inherit guest_primary_folio]) ? choice : "exception") : attrs["mode"].to_s
            party_id = choice&.delete_prefix("party:").presence || attrs["billing_party_id"].presence
            parent_party_id = attributes.to_h["billing_party_id"].to_s
            mode = "inherit" if party_id.to_s == parent_party_id
            unless mode.in?(%w[inherit exception guest_primary_folio])
              @error = "Choose whether the attached item follows its parent or uses an exception."
              next
            end
            if mode == "inherit"
              next unless child.rule
              { row:, child:, mode:, folio: row.target_folio }
            elsif mode == "guest_primary_folio"
              folio = @booking.booking_folio
              unless folio&.open?
                @error = "Guest primary folio must be open."
                next
              end
              next if child.target_folio&.id == folio.id
              { row:, child:, mode: "exception", folio: }
            else
              folio = folios[attrs["target_folio_id"].to_s]
              unless folio&.open?
                @error = "Attached-item exceptions must target an open folio."
                next
              end
              unless folio.booking_billing_party_id.to_s == party_id.to_s
                @error = "Attached-item target folio must belong to the selected billing party."
                next
              end
              next if child.target_folio&.id == folio.id
              { row:, child:, mode:, folio: }
            end
          end
        end
      end
    end
  end
end
