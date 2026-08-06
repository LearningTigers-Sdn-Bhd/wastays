module NightAudits
  module Evaluation
    module Checks
      class MissingNightlyCharges
        REASON = "Booking folios have missing or incorrect nightly charges"

        def initialize(context:, serializer: SerializeItems.new, reconciliation: Folios::Charges::NightlyChargeReconciliation)
          @context = context
          @serializer = serializer
          @reconciliation = reconciliation
        end

        def call
          details = @context.nightly_charge_candidates.filter_map do |booking|
            next if booking.booking_folio.blank?

            result = @reconciliation.call(booking: booking, business_date: @context.business_date)
            next if result.valid?

            @serializer.booking(booking, REASON).merge("line_issues" => result.issues)
          end

          { "missing_nightly_charges" => details }
        end
      end
    end
  end
end
