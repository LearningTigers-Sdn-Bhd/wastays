# frozen_string_literal: true

# LEGACY: frozen pending booking-control-panel migration. Do not add features here.

module HotelPortal
  module Folios
    class RoutingRulesController < HotelPortal::BaseController
      include OffcanvasTransactionCompletion

      before_action :authorize_manage_folio_movements!
      before_action :set_booking
      before_action :set_routing_rule, only: %i[edit update deactivate]

      def new
        redirect_to canonical_billing_routes_path, status: :see_other
      end

      def edit
        redirect_to canonical_billing_routes_path, status: :see_other
      end

      def create
        redirect_to canonical_billing_routes_path, status: :see_other
      end

      def update
        redirect_to canonical_billing_routes_path, status: :see_other
      end

      def deactivate
        redirect_to canonical_billing_routes_path, status: :see_other
      end

      private

      def canonical_billing_routes_path
        billing_routes_hotel_booking_control_panel_path(current_hotel, @booking)
      end

      def set_booking
        @booking = current_hotel.bookings.includes(:booking_folios).find(params[:booking_id])
      end

      def set_routing_rule
        @routing_rule = @booking.folio_routing_rules.find(params[:routing_rule_id])
      end

      def assign_sheet_context(title:, description:, form_url:, form_method:, submit_label:)
        @sheet_title = title
        @sheet_description = description
        @form_url = form_url
        @form_method = form_method
        @submit_label = submit_label
        @folio_origin = params[:origin].presence
        @active_folio_id = params[:active_folio_id].presence
        @charge_codes = routable_charge_codes
        @attached_tax_rule_groups = attached_tax_rule_groups(@charge_codes)
        @target_folios = @booking.booking_folios.open.order(is_primary: :desc, folio_sequence: :asc, id: :asc)
      end

      def parent_routing_rule_params
        params.fetch(:folio_routing_rule, {}).permit(:transaction_code_id, :target_folio_id, :active)
      end

      def child_routing_rule_params
        params.fetch(:folio_routing_rule, {}).permit(child_rules: [ :transaction_code_id, :target_folio_id, :enabled ])[:child_rules] || {}
      end

      def save_with_log(operation_type, previous_attributes: nil)
        FolioRoutingRule.transaction do
          ::NightAudits::OperationalChangeGuard.call!(hotel: current_hotel, action: :update_folio)
          @routing_rule.save!
          sync_child_routing_rules!
          refresh_forecasts!
          log_operation!(operation_type, previous_attributes: previous_attributes)
        end
        true
      rescue ActiveRecord::RecordInvalid => e
        @routing_rule.errors.add(:base, e.record.errors.full_messages.to_sentence) if @routing_rule.errors.empty?
        false
      end

      def log_operation!(operation_type, previous_attributes: nil)
        FolioOperationLog.create!(
          hotel: current_hotel,
          booking: @booking,
          actor: current_user,
          operation_type: operation_type,
          target_folio: @routing_rule.target_folio,
          currency: @routing_rule.target_folio&.currency || @booking.currency,
          metadata: {
            folio_routing_rule_id: @routing_rule.id,
            transaction_code_id: @routing_rule.transaction_code_id,
            transaction_code_code: @routing_rule.transaction_code&.code,
            target_folio_id: @routing_rule.target_folio_id,
            target_folio_reference: @routing_rule.target_folio&.folio_reference_display,
            previous: previous_attributes
          }.compact
        )
      end

      def tracked_attributes(rule)
        {
          transaction_code_id: rule.transaction_code_id,
          target_folio_id: rule.target_folio_id,
          active: rule.active
        }
      end

      def sync_child_routing_rules!
        child_routing_rule_params.to_h.each_value do |attributes|
          attributes = attributes.with_indifferent_access
          next unless ActiveModel::Type::Boolean.new.cast(attributes[:enabled])

          child_transaction_code = current_hotel.transaction_codes.find_by(id: attributes[:transaction_code_id])
          next if child_transaction_code.blank?

          target_folio_id = attributes[:target_folio_id].presence
          active_child_rule = @booking.folio_routing_rules.active.find_by(transaction_code: child_transaction_code)

          if target_folio_id.blank? || target_folio_id.to_s == @routing_rule.target_folio_id.to_s
            active_child_rule&.update!(active: false, updated_by: current_user)
            next
          end

          child_rule = active_child_rule || @booking.folio_routing_rules.build(
            hotel: current_hotel,
            transaction_code: child_transaction_code,
            created_by: current_user
          )
          child_rule.assign_attributes(target_folio_id: target_folio_id, active: true, updated_by: current_user)
          child_rule.save!
        end
      end

      def refresh_forecasts!
        primary_folio = @booking.booking_folio
        ::Folios::SyncForecastedCharges.call(booking_folio: primary_folio) if primary_folio.present?
      end

      def routable_charge_codes
        codes = current_hotel.transaction_codes.active.charge.includes(:transaction_code_taxes).order(:code).to_a
        hotel_tax_code_ids = current_hotel.hotel_taxes.where(transaction_code_id: codes.map(&:id)).pluck(:transaction_code_id)

        codes.reject { |code| hotel_tax_code_ids.include?(code.id) && !code.system_required? }
      end

      def attached_tax_rule_groups(charge_codes)
        active_rules = @booking.folio_routing_rules.active.includes(:target_folio).index_by(&:transaction_code_id)
        charge_codes.each_with_object({}) do |charge_code, groups|
          rules = charge_code.transaction_code_taxes.includes(:hotel_tax).filter_map do |tax_rule|
            child_code = tax_rule.posting_transaction_code
            next if child_code.blank?

            {
              transaction_code_id: child_code.id,
              display_code: "#{charge_code.code}_#{child_code.code}",
              name: tax_rule.display_name,
              enabled: tax_rule.enabled_for_posting?,
              selected_folio_id: active_rules[child_code.id]&.target_folio_id
            }
          end
          groups[charge_code.id] = rules if rules.any?
        end
      end

      def folio_path_for_billing
        hotel_booking_control_panel_path(
          current_hotel,
          @booking,
          tab: "billing_preferences",
          folio_id: params[:active_folio_id].presence
        )
      end

      def folio_origin_params
        params[:origin] == "folios" || params[:folio_origin] == "folios" ? { origin: "folios" } : {}
      end

      def authorize_manage_folio_movements!
        allowed = current_user.respond_to?(:superadmin?) && current_user.superadmin? ||
          current_user.has_permission?("manage_folio_movements", hotel: current_hotel)
        raise Pundit::NotAuthorizedError unless allowed
      end

      def respond_with_offcanvas_completion(destination, notice: nil, alert: nil)
        respond_to do |format|
          format.turbo_stream do
            flash[:notice] = notice if notice.present?
            flash[:alert] = alert if alert.present?
            render_offcanvas_completion(destination)
          end
          format.html { redirect_to destination, { notice: notice, alert: alert }.compact }
        end
      end
    end
  end
end
