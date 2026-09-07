# frozen_string_literal: true

module HotelPortal
  # External accounts index plus the Sheet-based invite and edit forms.
  #
  # Routes stay REST; only the rendering and completion contract are Sheet-based.
  # On failure the form is re-rendered into the sheet frame so submitted values
  # survive — the operator has to be able to correct an address in place.
  class CorporateAccountsController < HotelPortal::FinancialsBaseController
    include SheetActionCompletion

    SHEET_FRAME = "external_account_sheet"

    before_action :authorize_manage_corporate_accounts!
    before_action :set_relationship, only: %i[edit update suspend reactivate]
    before_action :set_return_to, except: :index

    def index
      @presenter = HotelPortal::AccountsReceivable::CorporateAccountsPresenter.new(hotel: current_hotel, params: params, request: request)
    end

    def new
      @corporate_invitation = current_hotel.corporate_invitations.build(
        relationship_type: "standard",
        credit_currency: current_hotel.default_currency
      )
      render :new, layout: false
    end

    def create
      result = CorporateInvitations::CreateService.new(
        hotel: current_hotel,
        invited_by_user: current_user,
        attributes: corporate_invitation_params
      ).call

      if result.success?
        complete_action(notice: "Invitation sent to #{result.invitation.email}.")
      else
        @corporate_invitation = result.invitation ||
          current_hotel.corporate_invitations.build(corporate_invitation_params)
        @corporate_invitation.errors.add(:base, result.error)
        render_failure("hotel_portal/corporate_accounts/invitation_form")
      end
    end

    def edit
      render :edit, layout: false
    end

    def update
      if @relationship.update(relationship_params)
        complete_action(notice: "#{@relationship.corporate_account.name} updated.")
      else
        render_failure("hotel_portal/corporate_accounts/relationship_form")
      end
    end

    def suspend
      @relationship.suspend!
      complete_action(notice: "#{@relationship.corporate_account.name} suspended.")
    end

    def reactivate
      @relationship.reactivate!
      complete_action(notice: "#{@relationship.corporate_account.name} reactivated.")
    end

    private

    def complete_action(notice:)
      complete_sheet_action(destination: @return_to, notice: notice, frame: requesting_sheet_frame)
    end

    # Re-render the form inside the sheet rather than closing it, so the
    # operator keeps what they typed and can fix it in place.
    def render_failure(partial)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update(requesting_sheet_frame, partial: partial),
            status: :unprocessable_content
        end
        format.html { render(action_name == "create" ? :new : :edit, layout: false, status: :unprocessable_content) }
      end
    end

    # Echo the frame that launched the sheet, so a stacked launcher closes its
    # own dialog rather than the primary one.
    def requesting_sheet_frame
      turbo_frame_request_id.presence || SHEET_FRAME
    end

    def set_return_to
      @return_to = sheet_action_return_to(fallback: hotel_corporate_accounts_path(current_hotel))
    end

    def authorize_manage_corporate_accounts!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_corporate_accounts", hotel: current_hotel)
    end

    def set_relationship
      @relationship = current_hotel.hotel_corporate_accounts.find(params[:id])
    end

    def corporate_invitation_params
      params.require(:corporate_invitation).permit(
        :email,
        :account_type,
        :relationship_type,
        :credit_limit,
        :credit_currency,
        :payment_terms_days
      )
    end

    def relationship_params
      params.require(:hotel_corporate_account).permit(
        :account_type,
        :relationship_type,
        :credit_limit,
        :credit_currency,
        :payment_terms_days,
        :contact_email,
        :contact_phone,
        :billing_address_line1,
        :billing_address_line2,
        :billing_city,
        :billing_state,
        :billing_postal_code,
        :billing_country,
        :auto_allocate_payments,
        :tin,
        :brn,
        :sst_registration_number
      )
    end
  end
end
