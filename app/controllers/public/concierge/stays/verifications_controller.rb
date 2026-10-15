module Public
  module Concierge
    module Stays
      # Turns a verified code into a stay session for this one browser. Another
      # browser keeps its own session, because the record holds no device state.
      class VerificationsController < BaseController
        skip_before_action :require_stay_session

        RECOVERY_NOTICE = "If this stay is with us, a new link is on its way to the booking email."

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

        # The way out of a lock. The mail goes to the booking email, which the
        # guest never types here, so a stranger with the URL learns nothing.
        def recover
          ::Concierge::StayAccess::SendLink.new(
            booking: @stay_access.booking,
            reason: :recovery
          ).call

          # One answer for every outcome, including a send that hit the cap. The
          # page must not say whether the mail went out.
          @notice = RECOVERY_NOTICE
          @locked = @stay_access.locked?
          render_stay_locked
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
