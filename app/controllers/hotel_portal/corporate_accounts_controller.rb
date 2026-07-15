# frozen_string_literal: true

module HotelPortal
  class CorporateAccountsController < HotelPortal::BaseController
    include OffcanvasTransactionCompletion

    before_action :authorize_manage_corporate_accounts!
    before_action :set_relationship, only: %i[edit update suspend reactivate]

    def index
      @presenter = HotelPortal::AccountsReceivable::CorporateAccountsPresenter.new(hotel: current_hotel, params: params)
      @pending_invitations = current_hotel.corporate_invitations
        .unaccepted
        .includes(:invited_by_user)
        .order(created_at: :desc)
    end

    def new
      @corporate_invitation = current_hotel.corporate_invitations.build(
        relationship_type: "standard",
        credit_currency: current_hotel.default_currency
      )
    end

    def create
      result = CorporateInvitations::CreateService.new(
        hotel: current_hotel,
        invited_by_user: current_user,
        attributes: corporate_invitation_params
      ).call

      if result.success?
        offcanvas_transaction_response(
          destination: hotel_corporate_accounts_path(current_hotel),
          notice: "Corporate invitation sent to #{result.invitation.email}."
        )
      else
        @corporate_invitation = result.invitation ||
          current_hotel.corporate_invitations.build(corporate_invitation_params)
        @corporate_invitation.errors.add(:base, result.error)
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      if @relationship.update(relationship_params)
        offcanvas_transaction_response(
          destination: hotel_corporate_accounts_path(current_hotel),
          notice: "#{@relationship.corporate_account.name} updated."
        )
      else
        render :edit, status: :unprocessable_content
      end
    end

    def suspend
      @relationship.suspend!
      redirect_to hotel_corporate_accounts_path(current_hotel), notice: "Corporate relationship suspended."
    end

    def reactivate
      @relationship.reactivate!
      redirect_to hotel_corporate_accounts_path(current_hotel), notice: "Corporate relationship reactivated."
    end

    private

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
        :contact_phone
      )
    end
  end
end
