# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      class BillingPartiesController < BaseController
        MODES = %w[choose add_account edit_terms remove].freeze

        before_action :set_mode
        before_action :set_party, if: -> { @mode.in?(%w[edit_terms remove]) }
        before_action :prepare_form

        def show
          return create if request.post? && @mode == "add_account"
          return update if request.patch? && @mode == "edit_terms"
          return destroy if request.delete? && @mode == "remove"
          raise ActiveRecord::RecordNotFound unless request.get?

          render :show, layout: false
        end

        private

        def set_mode
          @mode = params[:mode].presence_in(MODES) || "choose"
        end

        def set_party
          @party = @booking.booking_billing_parties.active.find(params[:billing_party_id])
        end

        def prepare_form
          @accounts = current_hotel.hotel_corporate_accounts.active
            .joins(:corporate_account).includes(:corporate_account).order("accounts.name")
          @billing_party_attributes = billing_party_params.to_h.with_indifferent_access
          @errors ||= []
        end

        def create
          target = resolved_target
          if target == :group && params[:confirm_group] != "1"
            @review_group = true
            return render_review
          end

          result = if target == :group
            BookingBillingParties::ManageCompany.call_for_group(
              group_booking: @booking.group_booking,
              actor: current_user,
              attributes: billing_party_params.except(:apply_to)
            )
          else
            BookingBillingParties::ManageCompany.call(
              booking: target,
              actor: current_user,
              attributes: billing_party_params.except(:apply_to)
            )
          end

          return complete_action(notice: "Billing party added.") if result.success?

          @errors = [ result.error ]
          render_failure
        end

        def update
          result = if billing_party_params[:apply_to] == "group"
            BookingBillingParties::UpdateGroupTerms.call(
              party: @party,
              actor: current_user,
              attributes: billing_terms_attributes
            )
          else
            BookingBillingParties::UpdateTerms.call(
              party: @party,
              actor: current_user,
              attributes: billing_terms_attributes
            )
          end

          return complete_action(notice: "Billing terms saved.") if result.success?

          @errors = result.respond_to?(:errors) ? result.errors : [ result.error ]
          render_failure
        end

        def destroy
          unless @party.archiveable?
            @errors = [ "Billing parties with folios cannot be removed." ]
            return render_failure
          end

          @party.update!(archived_at: Time.current)
          BookingAuditLog.create!(
            hotel: current_hotel, auditable: @booking, user: current_user,
            action_type: "billing_party_archived", category: "financial", source: "booking_workspace",
            occurred_at: Time.current, old_value: { billing_party_id: @party.id, party: @party.display_name }
          )
          complete_action(notice: "Billing party removed.")
        end

        def resolved_target
          value = billing_party_params[:apply_to].presence
          return @booking if @booking.group_booking_id.blank?
          return :group if value == "group"

          id = value.to_s.delete_prefix("booking:")
          @booking.group_booking.bookings.where(hotel_id: current_hotel.id).find(id)
        end

        def billing_party_params
          params.fetch(:billing_party, ActionController::Parameters.new).permit(
            :apply_to, :hotel_corporate_account_id, :account_type, :settlement_type,
            :purchase_order_reference, :authorization_reference
          )
        end

        def billing_terms_attributes
          billing_party_params.slice(:settlement_type, :purchase_order_reference, :authorization_reference)
        end

        def render_failure
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.update(
                requesting_sheet_frame,
                partial: "hotel_portal/bookings/actions/billing_parties/form"
              ), status: :unprocessable_content
            end
            format.html { render :show, layout: false, status: :unprocessable_content }
          end
        end

        def render_review
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.update(
                requesting_sheet_frame,
                partial: "hotel_portal/bookings/actions/billing_parties/form"
              )
            end
            format.html { render :show, layout: false }
          end
        end
      end
    end
  end
end
