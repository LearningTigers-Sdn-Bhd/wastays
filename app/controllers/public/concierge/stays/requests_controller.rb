module Public
  module Concierge
    module Stays
      # Housekeeping and complaints. The public page asks for a confirmation
      # code first; here the stay session already answered that.
      class RequestsController < BaseController
        def new
          @presenter = stay_presenter
          @kind = requested_kind
        end

        def create
          result = ::Concierge::SubmitGuestRequest.new(
            booking: stay_booking,
            kind: params[:kind],
            details: params[:details]
          ).call

          if result.success?
            redirect_to stay_path, notice: "We have your request. The property team is on it."
          else
            @presenter = stay_presenter
            @kind = requested_kind
            @error = result.message
            render :new, status: :unprocessable_content
          end
        end

        private

        def requested_kind
          kind = params[:kind].to_s
          kind.in?(::Concierge::SubmitGuestRequest::ALLOWED_KINDS) ? kind : "housekeeping"
        end
      end
    end
  end
end
