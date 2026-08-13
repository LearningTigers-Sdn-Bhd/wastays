# frozen_string_literal: true

module Admin
  module Hotels
    class CreateForm
      include ActiveModel::Model

      ACTIONS = %w[create_only create_and_onboard].freeze
      CHANNEL_MANAGER_OPTIONS = [
        [ "Undecided", "undecided" ],
        [ "No channel manager", "none" ],
        [ "Channex", "channex" ]
      ].freeze

      attr_accessor :account_name, :owner_name, :owner_email, :hotel_name, :sell_mode,
                    :plan_id, :preferred_channel_manager, :salesperson_id, :creation_action
      attr_reader :hotel, :owner_invitation

      validates :account_name, :owner_name, :owner_email, :hotel_name, :sell_mode, :plan_id,
                :preferred_channel_manager, :creation_action, presence: true
      validates :owner_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
      validates :sell_mode, inclusion: { in: ->(_) { RatePlan.sell_modes } }, allow_blank: true
      validates :preferred_channel_manager,
                inclusion: { in: CHANNEL_MANAGER_OPTIONS.map(&:last) }, allow_blank: true
      validates :creation_action, inclusion: { in: ACTIONS }, allow_blank: true
      validate :plan_is_active

      def initialize(attributes = {})
        super
        self.preferred_channel_manager ||= "undecided"
        self.creation_action ||= "create_only"
      end

      def save(actor:)
        return false unless valid?

        result = HotelOps::CreateHotel.new(
          account_params: { name: account_name },
          user_params: { name: owner_name, email: owner_email },
          hotel_params: {
            name: hotel_name,
            status: "setup",
            sell_mode: sell_mode,
            plan_id: plan_id,
            salesperson_id: salesperson_id.presence,
            preferred_channel_manager: preferred_channel_manager
          },
          owner_invitation: {
            invited_by: actor,
            deliver: creation_action == "create_and_onboard"
          }
        ).call

        if result[:success]
          @hotel = result[:hotel]
          @owner_invitation = result[:owner_invitation]
          true
        else
          errors.add(:base, result[:error])
          false
        end
      end

      def create_and_onboard?
        creation_action == "create_and_onboard"
      end

      private

      def plan_is_active
        return if plan_id.blank? || Plan.active.exists?(id: plan_id)

        errors.add(:plan_id, "must be an active subscription plan")
      end
    end
  end
end
