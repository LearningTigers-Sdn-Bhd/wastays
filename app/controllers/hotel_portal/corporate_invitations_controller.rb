# frozen_string_literal: true

module HotelPortal
  class CorporateInvitationsController < HotelPortal::BaseController
    before_action :authorize_manage_corporate_accounts!
    before_action :set_invitation

    def resend
      # A company queued during property setup with the send switch off reaches
      # this action never having been emailed, so the notice reports a first
      # send rather than claiming a repeat.
      verb = @invitation.sent? ? "resent" : "sent"

      if CorporateInvitations::ResendService.new(invitation: @invitation, invited_by_user: current_user).call
        respond_with_results(notice: "Invitation #{verb} to #{@invitation.email}.")
      else
        respond_with_results(alert: "Unable to send this invitation.")
      end
    end

    def destroy
      email = @invitation.email
      @invitation.destroy!
      respond_with_results(notice: "Invitation to #{email} revoked.")
    end

    private

    # Re-render the results frame in place so the operator keeps their search, tab,
    # and page instead of being bounced to an unfiltered index.
    def respond_with_results(notice: nil, alert: nil)
      @presenter = HotelPortal::AccountsReceivable::CorporateAccountsPresenter.new(
        hotel: current_hotel,
        params: results_params,
        request: pagination_request
      )

      respond_to do |format|
        format.turbo_stream do
          flash.now[:notice] = notice if notice
          flash.now[:alert] = alert if alert
          render "hotel_portal/corporate_accounts/results"
        end
        format.html { redirect_to hotel_corporate_accounts_path(current_hotel, results_params), notice: notice, alert: alert }
      end
    end

    def results_params
      params.permit(:query, :status, :account_type, :page)
    end

    def pagination_request
      {
        base_url: request.base_url,
        path: hotel_corporate_accounts_path(current_hotel),
        params: results_params.to_h
      }
    end

    def authorize_manage_corporate_accounts!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_corporate_accounts", hotel: current_hotel)
    end

    def set_invitation
      @invitation = current_hotel.corporate_invitations.unaccepted.find(params[:id])
    end
  end
end
