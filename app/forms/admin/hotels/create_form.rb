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

      # Long enough that the one-time temporary password is not worth guessing,
      # short enough to read aloud over the phone to the owner.
      GENERATED_PASSWORD_LENGTH = 16

      attr_accessor :account_name, :owner_name, :owner_email, :hotel_name, :sell_mode,
                    :plan_id, :preferred_channel_manager, :salesperson_id, :creation_action,
                    :verify_owner_account
      attr_reader :hotel, :owner, :owner_invitation, :generated_password

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

        password = (SecureRandom.alphanumeric(GENERATED_PASSWORD_LENGTH) if verify_owner_account?)

        result = HotelOps::CreateHotel.new(
          account_params: { name: account_name },
          user_params: owner_params(password),
          hotel_params: {
            name: hotel_name,
            status: "setup",
            sell_mode: sell_mode,
            plan_id: plan_id,
            salesperson_id: salesperson_id.presence,
            preferred_channel_manager: preferred_channel_manager
          },
          # A nil invitation is what tells CreateHotel to provision the owner
          # user directly instead of waiting for an activation link.
          owner_invitation: owner_invitation_options(actor)
        ).call

        if result[:success]
          @hotel = result[:hotel]
          @owner = result[:user]
          @owner_invitation = result[:owner_invitation]
          @generated_password = password
          true
        else
          errors.add(:base, result[:error])
          false
        end
      end

      def create_and_onboard?
        creation_action == "create_and_onboard"
      end

      def verify_owner_account?
        ActiveModel::Type::Boolean.new.cast(verify_owner_account).present?
      end

      private

      def owner_params(password)
        base = { name: owner_name, email: owner_email }
        return base if password.blank?

        base.merge(password: password, password_confirmation: password)
      end

      def owner_invitation_options(actor)
        return nil if verify_owner_account?

        { invited_by: actor, deliver: create_and_onboard? }
      end

      def plan_is_active
        return if plan_id.blank? || Plan.active.exists?(id: plan_id)

        errors.add(:plan_id, "must be an active subscription plan")
      end
    end
  end
end
