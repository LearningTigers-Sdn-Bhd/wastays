# frozen_string_literal: true

module HotelPortal
  class OtaFinancialSettingsController < HotelPortal::SettingsBaseController
    before_action :authorize_ota_financial_settings!
    before_action :set_policy

    def show
      prepare_page
    end

    def approve_adjustment
      snapshot = OtaFinancialSnapshot.current.find_by!(hotel: current_hotel, id: params.require(:snapshot_id))
      result = ChannelManagers::Financials::ApproveAdjustmentProposal.call(snapshot: snapshot, user: current_user)
      if result.success?
        redirect_to hotel_ota_financial_settings_path(current_hotel), notice: "OTA adjustment approved and posted."
      else
        redirect_to hotel_ota_financial_settings_path(current_hotel), alert: result.error
      end
    end

    def update
      prepare_presenter
      @form = HotelPortal::OtaFinancialSettingsForm.new(
        hotel: current_hotel,
        policy: @policy,
        candidates: @presenter.mapping_candidates,
        current_user: current_user,
        attributes: ota_financial_settings_params
      )

      if @form.save
        redirect_to hotel_ota_financial_settings_path(current_hotel), notice: "OTA financial settings updated."
      else
        render :show, status: :unprocessable_content
      end
    end

    private

    def authorize_ota_financial_settings!
      authorize current_hotel, policy_class: OtaFinancialSettingsPolicy
    end

    def set_policy
      @policy = OtaRateVariancePolicy.find_or_initialize_by(hotel: current_hotel)
      return if @policy.persisted?

      @policy.assign_attributes(
        mode: "recommended",
        maximum_percentage: OtaRateVariancePolicy::RECOMMENDED_MAX_PERCENTAGE,
        maximum_amount_per_room_night: OtaRateVariancePolicy::RECOMMENDED_MAX_AMOUNT_PER_ROOM_NIGHT,
        currency: current_hotel.default_currency
      )
    end

    def prepare_page
      prepare_presenter
      @form = HotelPortal::OtaFinancialSettingsForm.new(
        hotel: current_hotel,
        policy: @policy,
        candidates: @presenter.mapping_candidates,
        current_user: current_user
      )
    end

    def prepare_presenter
      @presenter = HotelPortal::OtaFinancialSettingsPresenter.new(
        hotel: current_hotel, policy: @policy, user: current_user
      )
    end

    def ota_financial_settings_params
      params.require(:ota_financial_settings).permit(
        :mode,
        :maximum_percentage,
        :maximum_amount_per_room_night,
        mapping_transaction_code_ids: {}
      )
    end
  end
end
