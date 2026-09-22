module Public
  module Concierge
    module Stays
      # Turns a verified code into a stay session for this one browser. Another
      # browser keeps its own session, because the record holds no device state.
      class VerificationsController < BaseController
        skip_before_action :require_stay_session

        def create
          result = ::Concierge::StayAccess::VerifyDevice.new(
            stay_access: @stay_access,
            confirmation_code: params[:confirmation_token],
            request_ip: request.remote_ip
          ).call

          return render_failure(result) unless result.success?

          start_concierge_stay_session(result.stay_access, expires_at: @stay_expires_at)

          # The target is built from the hotel and the route, so no request value
          # can steer it. An open redirect is not possible here.
          redirect_to stay_path
        end

        private

        def render_failure(result)
          @error = result.error
          @locked = result.locked.present?
          @retry_after = result.retry_after
          render_stay_locked(status: :unprocessable_content)
        end
      end
    end
  end
end
