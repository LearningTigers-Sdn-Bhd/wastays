# frozen_string_literal: true

module AgentPortal
  module Hotels
    # The admin create form with the platform choices fixed. An agent enters
    # only the owner and how the hotel sells rooms. The server sets every
    # other value, so a changed request cannot pick a plan or a feature.
    class CreateForm < Admin::Hotels::CreateForm
      AGENT_FIELDS = %i[account_name owner_name owner_email owner_password hotel_name sell_mode].freeze

      # Optional. Empty means the system makes the owner a password.
      attr_accessor :owner_password

      validates :owner_password,
                length: { minimum: Admin::SuperAgents::CreateService::MINIMUM_PASSWORD_LENGTH },
                allow_blank: true

      def initialize(attributes = {})
        super(attributes.to_h.symbolize_keys.slice(*AGENT_FIELDS))
        assign_attributes(SuperAgents::HotelDefaults.call)
        self.creation_action = "create_only"
        self.verify_owner_account = true
      end

      private

      def new_owner_password
        owner_password.presence || super
      end
    end
  end
end
