# frozen_string_literal: true

module HotelPortal
  class CorporateAccountAdditionsController < FinancialsBaseController
    include SheetActionCompletion

    before_action :authorize!
    before_action :prepare_form

    def new
      render :new, formats: :html, layout: false
    end

    def lookup
      resolve_email
      render_form(status: @lookup_ready ? :ok : :unprocessable_content)
    end

    def create
      result = CorporateAccounts::Create.call(hotel: current_hotel, attributes: @attributes)
      if result.success?
        if result.created
          @credential_user = result.user
          response.headers["Cache-Control"] = "no-store"
          respond_to do |format|
            format.turbo_stream { render turbo_stream: turbo_stream.update(sheet_frame, partial: "hotel_portal/corporate_account_passwords/credentials") }
            format.html { render "hotel_portal/corporate_account_passwords/show", layout: false }
          end
        else
          complete_sheet_action(destination: @return_to, notice: "#{result.user.account.name} linked to this hotel.", frame: sheet_frame)
        end
      else
        resolve_email
        @relationship.errors.add(:base, result.error) unless @relationship.errors.full_messages.include?(result.error)
        render_form(status: :unprocessable_content)
      end
    end

    private

    def authorize!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_corporate_accounts", hotel: current_hotel)
    end

    def prepare_form
      @return_to = sheet_action_return_to(fallback: hotel_corporate_accounts_path(current_hotel))
      @attributes = params.fetch(:corporate_account_addition, ActionController::Parameters.new).permit(:email, :account_name, :name,
        *CorporateAccounts::Create::RELATIONSHIP_ATTRIBUTES).to_h.symbolize_keys
      @relationship = current_hotel.hotel_corporate_accounts.build(
        { relationship_type: "direct_bill", credit_currency: current_hotel.default_currency, account_type: "company" }
          .merge(@attributes.slice(*CorporateAccounts::Create::RELATIONSHIP_ATTRIBUTES))
      )
    end

    def resolve_email
      result = CorporateAccounts::Lookup.call(hotel: current_hotel, email: @attributes[:email])
      @lookup_ready = result.success?
      @existing_user = result.user
      @relationship.errors.add(:base, result.error) unless result.success?
    end

    def render_form(status:)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.update(sheet_frame, partial: "hotel_portal/corporate_account_additions/form"), status: status }
        format.html { render :new, layout: false, status: status }
      end
    end

    def sheet_frame
      turbo_frame_request_id.presence || CorporateAccountsController::SHEET_FRAME
    end
  end
end
